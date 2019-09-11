# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Jobs::ConfirmAkismetFlaggedPosts do
  describe '#execute' do
    let(:user) { Fabricate(:user) }

    it 'raises an exception if :user_id is not provided' do
      expect do
        subject.execute({})
      end.to raise_error(Discourse::InvalidParameters)
    end

    it 'raises an exception if :performed_by_id is not provided' do
      expect do
        subject.execute(user_id: user.id)
      end.to raise_error(Discourse::InvalidParameters)
    end

    let(:admin) { Fabricate(:admin) }

    before do
      @user_post_reviewable = reviewable_post_for(user)
    end

    it 'approves every flagged post' do
      subject.execute(user_id: user.id, performed_by_id: admin.id)

      updated_post_reviewable = @user_post_reviewable.reload

      expect(updated_post_reviewable.status).to eq(Reviewable.statuses[:approved])
    end

    it 'approves every flagged post even if the post was already deleted' do
      @user_post_reviewable.target.trash!
      subject.execute(user_id: user.id, performed_by_id: admin.id)

      updated_post_reviewable = @user_post_reviewable.reload

      expect(updated_post_reviewable.status).to eq(Reviewable.statuses[:approved])
    end

    it 'only approves pending flagged posts' do
      @user_post_reviewable.perform(admin, :confirm_spam)
      last_update = @user_post_reviewable.updated_at
      subject.execute(user_id: user.id, performed_by_id: admin.id)

      updated_post_reviewable = @user_post_reviewable.reload

      expect(updated_post_reviewable.updated_at).to eq(last_update)
    end
  end

  def reviewable_post_for(user)
    post = Fabricate(:post, user: user)
    ReviewableAkismetPost.needs_review!(target: post, created_by: admin)
  end
end
