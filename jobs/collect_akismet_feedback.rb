module Jobs
  class CollectAkismetFeedback < ::Jobs::Scheduled
    every 15.minutes

    def execute(args)
      return unless SiteSetting.akismet_enabled?
      return if SiteSetting.akismet_api_key.blank?
      return unless defined?(Reviewable)

      statuses = [Reviewable.statuses[:approved], Reviewable.statuses[:rejected]]
      post_ids = PostCustomField.where(name: 'AKISMET_STATE', value: 'needs_review').pluck(:post_id)
      reviews = ReviewableFlaggedPost.select(:target_id, :target_type, :status).includes(:target)
        .where(target_id: post_ids, target_type: Post.name)
        .where(status: statuses)

      reviews.each do |review|
        approved = review.status == Reviewable.statuses[:approved]
        result = approved ? 'ham' : 'spam'

        DiscourseAkismet.move_to_state(review.target, "confirmed_#{result}")
        Jobs.enqueue(:update_akismet_status, post_id: review.target_id, status: result) if approved
      end
    end
  end
end
