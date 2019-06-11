# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::CheckAkismetPost do
  before { SiteSetting.akismet_enabled = true }

  describe '#execute' do
    it 'does not create a reviewable when a reviewable queued post already exists for that target' do
      post = Fabricate(:post)
      ReviewableQueuedPost.needs_review!(target: post, created_by: Discourse.system_user)

      subject.execute(post_id: post.id)

      expect(ReviewableAkismetPost.count).to be_zero
    end
  end
end
