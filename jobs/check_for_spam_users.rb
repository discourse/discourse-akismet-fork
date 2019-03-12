module Jobs
  class CheckForSpamUsers < ::Jobs::Scheduled
    every 10.minutes

    def execute(args = {})
      return unless SiteSetting.akismet_enabled?
      return if SiteSetting.akismet_api_key.blank?

      DiscourseAkismet::CheckSpamUser.to_check.find_each do |user|
        DiscourseAkismet::CheckSpamUser.new(user, user.user_profile.bio_raw).check_for_spam
      end
    end
  end
end
