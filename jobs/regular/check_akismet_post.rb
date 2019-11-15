# frozen_string_literal: true

module Jobs
  class CheckAkismetPost < ::Jobs::Base

    # Check a single post for spam. We do this for TL0 to get a faster response
    # without batching.
    def execute(args)
      return unless SiteSetting.akismet_enabled?

      post = Post.find_by(id: args[:post_id], user_deleted: false)
      return if post.blank?

      return if ReviewableQueuedPost.exists?(target: post)

      client = Akismet::Client.build_client
      DiscourseAkismet::PostsBouncer.new.perform_check(client, post)
    end
  end
end
