# frozen_string_literal: true

module Jobs
  class CheckUsersForSpam < ::Jobs::Base
    def execute(args)
      user = User.includes(:user_profile).find_by(id: args[:user_id])
      raise Discourse::InvalidParameters.new(:user_id) unless user.present?

      client = Akismet::Client.build_client
      DiscourseAkismet::UsersBouncer.new.perform_check(client, user)
    end
  end
end
