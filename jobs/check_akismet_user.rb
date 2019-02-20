module Jobs
  class CheckAkismetUser < Jobs::Base

    def execute(args)
      return if args[:user_id].blank?

      return unless user = User.find_by(id: args[:user_id])

      DiscourseAkismet::CheckSpamUser.new(user).check_for_spam
    end
  end
end
