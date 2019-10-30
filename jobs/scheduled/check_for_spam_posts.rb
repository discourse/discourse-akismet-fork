# frozen_string_literal: true

module Jobs
  class CheckForSpamPosts < ::Jobs::Scheduled
    every 10.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return if SiteSetting.akismet_api_key.blank?

      # Users above TL0 are checked in batches
      to_check = DiscourseAkismet::PostsBouncer.to_check
        .includes(post: :user)
        .where('users.trust_level > 0')
        .where('posts.user_deleted = false').map(&:post)

      spam_count = 0
      bouncer = DiscourseAkismet::PostsBouncer.new
      client = Akismet::Client.build_client

      [to_check].flatten.each do |post|
        result = bouncer.perform_check(client, post)
        spam_count += 1 if result
      end

      # Trigger an event that akismet found spam. This allows people to
      # notify chat rooms or whatnot
      DiscourseEvent.trigger(:akismet_found_spam, spam_count) if spam_count > 0
    end
  end
end
