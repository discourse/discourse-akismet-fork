module Jobs
  class CheckAkismetUser < Jobs::Base

    def execute(args)
      return if args[:user_id].blank?

      user = User.where(id: args[:user_id]).first

      return if user.blank?

      DiscourseAkismet::User.new(user).check_for_spam
    end
  end
end
