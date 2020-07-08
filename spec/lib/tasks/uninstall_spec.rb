# frozen_string_literal: true

require 'rails_helper'

describe 'Uninstall plugin rake task' do
  describe '#remove_reviewables' do
    let(:flagged_post) { Fabricate(:reviewable_flagged_post) }

    let(:akismet_flagged_reviewable) { Fabricate(:reviewable_akismet_post) }
    let(:akismet_flagged_post) { akismet_flagged_reviewable.target }
    let(:akismet_flagged_user) { Fabricate(:reviewable_akismet_user) }

    before do
      Rake::Task.clear
      Discourse::Application.load_tasks

      SiteSetting.akismet_api_key = 'fake_key'
      DiscourseAkismet::Bouncer.new.move_to_state(akismet_flagged_post, 'confirmed_spam')

      add_score(flagged_post)
      add_score(akismet_flagged_user)
      add_score(akismet_flagged_reviewable)
    end

    it 'deletes reviewable objects' do
      run_task

      expect { akismet_flagged_reviewable.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect { akismet_flagged_user.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(flagged_post.reload).to be_present
    end

    it 'deletes the scores of those reviewable objects' do
      expect(object_exists?(ReviewableScore, akismet_flagged_reviewable)).to eq(true)
      expect(object_exists?(ReviewableScore, akismet_flagged_user)).to eq(true)
      expect(object_exists?(ReviewableScore, flagged_post)).to eq(true)

      run_task

      expect(object_exists?(ReviewableScore, akismet_flagged_reviewable)).to eq(false)
      expect(object_exists?(ReviewableScore, akismet_flagged_user)).to eq(false)
      expect(object_exists?(ReviewableScore, flagged_post)).to eq(true)
    end

    it 'deletes the history of those reviewable objects' do
      admin = Fabricate(:admin)
      akismet_flagged_reviewable.perform(admin, :not_spam)
      akismet_flagged_user.perform(admin, :not_spam)
      flagged_post.perform(admin, :ignore)

      expect(object_exists?(ReviewableHistory, akismet_flagged_reviewable)).to eq(true)
      expect(object_exists?(ReviewableHistory, akismet_flagged_user)).to eq(true)
      expect(object_exists?(ReviewableHistory, flagged_post)).to eq(true)

      run_task

      expect(object_exists?(ReviewableHistory, akismet_flagged_reviewable)).to eq(false)
      expect(object_exists?(ReviewableHistory, akismet_flagged_user)).to eq(false)
      expect(object_exists?(ReviewableHistory, flagged_post)).to eq(true)
    end

    it 'removes akismet custom fields' do
      run_task

      akismet_custom_field = akismet_flagged_post
        .reload.custom_fields[DiscourseAkismet::Bouncer::AKISMET_STATE]

      expect(akismet_custom_field).to be_nil
    end

    def object_exists?(klass, reviewable)
      klass.where(reviewable_id: reviewable.id).exists?
    end

    def add_score(reviewable)
      reviewable.add_score(
        reviewable.created_by, PostActionType.types[:spam],
        created_at: reviewable.created_at, reason: 'spam'
      )
    end

    def run_task
      Rake::Task['akismet_uninstall:delete_reviewables'].invoke
    end
  end
end
