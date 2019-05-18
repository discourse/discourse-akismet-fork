# frozen_string_literal: true

module Jobs
  class CheckUsersForSpam < Jobs::Base
    def execute(args)
      user = User.includes(:user_profile).find_by(id: args[:user_id])
      raise Discourse::InvalidParameters.new(:user_id) unless user.present?

      DiscourseAkismet.with_client do |client|
        DiscourseAkismet::UsersBouncer.new.check_user(client, user)
      end
    end
  end
end
