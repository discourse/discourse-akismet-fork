module DiscourseAkismet

  def self.should_check_post?(post)
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

  def self.with_client
    Akismet::Client.with_client(
      api_key: SiteSetting.akismet_api_key,
      base_url: Discourse.base_url,
    ) do |client|

      yield client
    end
  end

  def self.args_for_post(post)
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

  def self.to_check
    PostCustomField.where(name: 'AKISMET_STATE', value: 'new')
      .where('posts.id IS NOT NULL')
      .where('topics.id IS NOT NULL')
      .includes(post: :topic)
      .references(:post, :topic)
  end

  def self.check_for_spam(to_check)
    return if to_check.blank?

    spam_count = 0
    DiscourseAkismet.with_client do |client|
      [to_check].flatten.each do |post|

        if post.user_deleted? || !post.topic
          DiscourseAkismet.move_to_state(post, 'skipped')
          next
        end

        # If the post is spam, mark it for review and destroy it
        if client.comment_check(DiscourseAkismet.args_for_post(post))
          spam_reporter = Discourse.system_user
          PostDestroyer.new(spam_reporter, post).destroy
          spam_count += 1
          DiscourseAkismet.move_to_state(post, 'needs_review')

          # Send a message to the user explaining that it happened
          if SiteSetting.akismet_notify_user?
            SystemMessage.new(post.user).create(
              'akismet_spam',
              topic_title: post.topic.title
            )
          end

          if defined?(ReviewableAkismetPost)
            ReviewableAkismetPost.needs_review!(
              created_by: spam_reporter, target: post, topic: post.topic, reviewable_by_moderator: true
            )
          end
        else
          DiscourseAkismet.move_to_state(post, 'checked')
        end
      end
    end

    # Trigger an event that akismet found spam. This allows people to
    # notify chat rooms or whatnot
    DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
  end

  def self.stats
    result = PostCustomField.where(name: 'AKISMET_STATE').group(:value).count.symbolize_keys!
    result[:confirmed_spam] ||= 0
    result[:confirmed_ham] ||= 0
    result[:needs_review] ||= 0
    result[:checked] ||= 0
    result[:scanned] = result[:checked] + result[:needs_review] + result[:confirmed_spam] + result[:confirmed_ham]
    result
  end

  def self.needs_review
    post_ids = PostCustomField.where(name: 'AKISMET_STATE', value: 'needs_review').pluck(:post_id)
    Post.with_deleted.where(id: post_ids).includes(:topic, :user).references(:topic)
  end

  def self.move_to_state(post, state, opts = nil)
    opts ||= {}
    return if post.blank? || SiteSetting.akismet_api_key.blank?

    to_update = {
      "AKISMET_STATE" => state
    }

    # Optional parameters to set
    to_update['AKISMET_IP_ADDRESS'] = opts[:ip_address] if opts[:ip_address].present?
    to_update['AKISMET_USER_AGENT'] = opts[:user_agent] if opts[:user_agent].present?
    to_update['AKISMET_REFERRER'] = opts[:referrer] if opts[:referrer].present?

    # New API in Discouse that's better under concurrency
    if post.respond_to?(:upsert_custom_fields)
      post.upsert_custom_fields(to_update)
    else
      post.custom_fields.merge!(to_update)
      post.save_custom_fields
    end

    # Publish the new review count via message bus
    msg = { akismet_review_count: DiscourseAkismet.needs_review.count }
    MessageBus.publish('/akismet_counts', msg, user_ids: User.staff.pluck(:id))
  end

  def self.munge_args(&block)
    @munger = block
  end

  def self.reset_munge
    @munger = nil
  end

  private

  def self.comment_content(post)
    post.is_first_post? ? "#{post.topic && post.topic.title}\n\n#{post.raw}" : post.raw
  end
end
