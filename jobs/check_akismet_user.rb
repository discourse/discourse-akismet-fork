module Jobs
  class CheckAkismetUser < Jobs::Base

    def execute(args)
      raise Discourse::InvalidParameters.new(:user_id) if args[:user_id].blank?
      raise Discourse::InvalidParameters.new(:profile_content) if args[:profile_content].blank?

      return unless user = User.find_by(id: args[:user_id])

      DiscourseAkismet::CheckSpamUser.new(user, args[:profile_content]).check_for_spam
    end
  end
end
