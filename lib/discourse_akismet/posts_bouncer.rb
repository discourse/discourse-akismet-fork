# frozen_string_literal: true

module DiscourseAkismet
  class PostsBouncer < Bouncer
    def self.to_check
      PostCustomField.where(name: 'AKISMET_STATE', value: 'new')
        .where('posts.id IS NOT NULL')
        .where('topics.id IS NOT NULL')
        .joins('LEFT OUTER JOIN reviewables ON reviewables.target_id = post_custom_fields.post_id')
        .where('reviewables.target_type IS NULL OR reviewables.type <> ?', ReviewableQueuedPost.name)
        .includes(post: :topic)
        .references(:post, :topic)
    end

    def should_check?(post)
      return false if post.blank? || (!SiteSetting.akismet_enabled?)

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

    def enqueue_for_check(post)
      return unless should_check?(post)
      Jobs.enqueue(:check_akismet_post, post_id: post.id)
    end

    def munge_args(&block)
      @munger = block
    end

    def reset_munge
      @munger = nil
    end

    def args_for(post)
      extra_args = {
        content_type: 'forum-post',
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

      @munger.call(extra_args) if @munger
      extra_args
    end

    private

    def before_check(post)
      return true unless post.user_deleted? || post.topic.nil?

      move_to_state(post, 'skipped')
      false
    end

    def mark_as_spam(post)
      PostDestroyer.new(spam_reporter, post).destroy
      move_to_state(post, 'needs_review')

      # Send a message to the user explaining that it happened
      notify_poster(post) if SiteSetting.akismet_notify_user?

      reviewable = ReviewableAkismetPost.needs_review!(
        created_by: spam_reporter, target: post, topic: post.topic, reviewable_by_moderator: true,
        payload: { post_cooked: post.cooked }
      )

      add_score(reviewable, 'akismet_spam_post')
    end

    def mark_as_clear(post)
      move_to_state(post, 'checked')
    end

    def notify_poster(post)
      SystemMessage.new(post.user).create('akismet_spam', topic_title: post.topic.title)
    end

    def comment_content(post)
      post.is_first_post? ? "#{post.topic && post.topic.title}\n\n#{post.raw}" : post.raw
    end
  end
end
