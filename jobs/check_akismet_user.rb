module Jobs
  class CheckAkismetUser < Jobs::Base

    def execute(args)
      return if args[:user_id].blank?

      user = User.find_by(id: args[:user_id])

      return if user.nil?

      DiscourseAkismet::User.new(user).check_for_spam
    end
  end
end
