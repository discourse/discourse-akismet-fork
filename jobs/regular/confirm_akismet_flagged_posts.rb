# frozen_string_literal: true

module Jobs
  class ConfirmAkismetFlaggedPosts < Jobs::Base
    def execute(args)
      raise Discourse::InvalidParameters.new(:user_id) unless args[:user_id]
      raise Discourse::InvalidParameters.new(:performed_by_id) unless args[:performed_by_id]

      performed_by = User.find_by(id: args[:performed_by_id])
      post_ids = Post.with_deleted.where(user_id: args[:user_id]).pluck(:id)

      ReviewableAkismetPost.where(target_id: post_ids, status: Reviewable.statuses[:pending]).find_each do |reviewable|
        reviewable.perform(performed_by, :confirm_spam)
      end
    end
  end
end
