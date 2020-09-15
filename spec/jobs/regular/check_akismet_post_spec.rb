# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::CheckAkismetPost do
  before { SiteSetting.akismet_enabled = true }

  describe '#execute' do
    let(:post) { Fabricate(:post) }

    it 'does not create a reviewable when a reviewable queued post already exists for that target' do
      ReviewableQueuedPost.needs_review!(target: post, created_by: Discourse.system_user)

      subject.execute(post_id: post.id)

      expect(ReviewableAkismetPost.count).to be_zero
    end

    it 'does not create a reviewable when a reviewable flagged post already exists for that target' do
      ReviewableFlaggedPost.needs_review!(target: post, created_by: Discourse.system_user)

      subject.execute(post_id: post.id)

      expect(ReviewableAkismetPost.count).to be_zero
    end

    it 'does not create a reviewable when the post is not spam' do
      Akismet::Client.any_instance.stubs(:comment_check).returns(false)

      subject.execute(post_id: post.id)

      expect(ReviewableAkismetPost.count).to be_zero
    end
  end
end
