# frozen_string_literal: true

module DiscourseAkismet
  class PostsBouncer < Bouncer
    CUSTOM_FIELDS = %w[
      AKISMET_STATE
      AKISMET_IP_ADDRESS
      AKISMET_USER_AGENT
      AKISMET_REFERRER
    ]
    TOPIC_DELETED_CHANNEL = "/discourse-akismet/topic-deleted/"

    @@munger = nil

    def self.to_check
      PostCustomField.where(name: 'AKISMET_STATE', value: 'new')
        .where('posts.id IS NOT NULL')
        .where('topics.id IS NOT NULL')
        .joins('LEFT OUTER JOIN reviewables ON reviewables.target_id = post_custom_fields.post_id')
        .where('reviewables.target_type IS NULL OR reviewables.type <> ?', ReviewableQueuedPost.name)
        .includes(post: :topic)
        .references(:post, :topic)
    end

    def suspect?(post)
      return false if post.blank? || post.topic.blank? || (!SiteSetting.akismet_enabled?)

      # We don't run akismet on private messages
      return false if post.topic.private_message?

      stripped = post.raw.strip

      # We only check posts over 20 chars
      return false if stripped.size < 20

      # Always check the first post of a TL1 user
      return true if post.user.trust_level == TrustLevel[1] && post.user.post_count == 0

      # We only check certain trust levels
      return false if post.user.has_trust_level?(TrustLevel[SiteSetting.skip_akismet_trust_level.to_i])

      # If a user is locked, we don't want to check them forever
      return false if post.user.post_count > SiteSetting.skip_akismet_posts.to_i

      # If the entire post is a URI we skip it. This might seem counter intuitive but
      # Discourse already has settings for max links and images for new users. If they
      # pass it means the administrator specifically allowed them.
      uri = URI(stripped) rescue nil
      return false if uri

      # Otherwise check the post!
      true
    end

    def store_additional_information(post, opts = {})
      values ||= {}
      return if post.blank? || SiteSetting.akismet_api_key.blank?

      # Optional parameters to set
      values['AKISMET_IP_ADDRESS'] = opts[:ip_address] if opts[:ip_address].present?
      values['AKISMET_USER_AGENT'] = opts[:user_agent] if opts[:user_agent].present?
      values['AKISMET_REFERRER'] = opts[:referrer] if opts[:referrer].present?

      post.upsert_custom_fields(values)
    end

    def clean_old_akismet_custom_fields
      PostCustomField
        .where(name: CUSTOM_FIELDS)
        .where('created_at <= ?', 2.months.ago)
        .delete_all
    end

    def self.munge_args(&block)
      @@munger = block
    end

    def self.reset_munge
      @@munger = nil
    end

    def args_for(post)
      extra_args = {
        blog: Discourse.base_url,
        content_type: post.is_first_post? ? 'forum-post' : 'reply',
        referrer: post.custom_fields['AKISMET_REFERRER'],
        permalink: "#{Discourse.base_url}#{post.url}",
        comment_author: post.user.try(:username),
        comment_content: comment_content(post),
        user_ip: post.custom_fields['AKISMET_IP_ADDRESS'],
        user_agent: post.custom_fields['AKISMET_USER_AGENT']
      }

      # Sending the email to akismet is optional
      if SiteSetting.akismet_transmit_email?
        extra_args[:comment_author_email] = post.user.try(:email)
      end

      @@munger.call(extra_args) if @@munger
      extra_args
    end

    private

    def enqueue_job(post)
      Jobs.enqueue(:check_akismet_post, post_id: post.id)
    end

    def before_check(post)
      return true unless post.user_deleted? || post.topic.nil?
      false
    end

    def mark_as_spam(post)
      PostDestroyer.new(spam_reporter, post).destroy

      # Send a message to the user explaining that it happened
      notify_poster(post) if SiteSetting.akismet_notify_user?

      if post.is_first_post?
        MessageBus.publish(
          [TOPIC_DELETED_CHANNEL, post.topic_id].join,
          "spam_found",
          user_ids: [post.user_id]
        )
      end

      reviewable = ReviewableAkismetPost.needs_review!(
        created_by: spam_reporter, target: post, topic: post.topic, reviewable_by_moderator: true,
        payload: { post_cooked: post.cooked }
      )

      add_score(reviewable, 'akismet_spam_post')
      move_to_state(post, 'confirmed_spam')
    end

    def mark_as_errored(post, reason)
      super do
        ReviewableAkismetPost.needs_review!(
          created_by: spam_reporter, target: post, topic: post.topic, reviewable_by_moderator: true,
          payload: { post_cooked: post.cooked, external_error: reason }
        )
      end
    end

    def notify_poster(post)
      SystemMessage.new(post.user).create('akismet_spam', topic_title: post.topic.title, post_link: post.full_url)
    end

    def comment_content(post)
      return post.raw unless post.is_first_post?

      topic = post.topic || Topic.with_deleted.find_by(id: post.topic_id)
      "#{topic && topic.title}\n\n#{post.raw}"
    end
  end
end
