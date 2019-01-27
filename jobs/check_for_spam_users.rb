module Jobs
  class CheckForSpamUsers < ::Jobs::Scheduled
    every 10.minutes

    def execute(args = {})
      return unless SiteSetting.akismet_enabled?
      return if SiteSetting.akismet_api_key.blank?

      DiscourseAkismet::User.to_check.each do |user|
        DiscourseAkismet::User.new(user).check_for_spam
      end
    end
  end
end
