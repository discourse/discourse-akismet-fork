require 'rails_helper'

describe 'Reviewables rake tasks' do

  before do
    Rake::Task.clear
    Discourse::Application.load_tasks
    SiteSetting.akismet_api_key = 'fake_key'
  end

  describe '#migrate_akismet_reviews' do
    let(:post) { Fabricate(:post) }

    %w[checked skipped new].each do |state|
      it "Does not migrate post that were tagged as #{state}" do
        DiscourseAkismet.move_to_state(post, state)

        Rake::Task['reviewables:migrate_akismet_reviews'].invoke
        created_reviewables = ReviewableAkismetPost.count

        expect(created_reviewables).to be_zero
      end
    end

    let(:admin) { Fabricate(:admin) }
    let(:system_user) { Discourse.system_user }

    %w[dismissed confirmed_spam confirmed_ham].each do |state|
      it "Migrates posts that were tagged as #{state}" do
        DiscourseAkismet.move_to_state(post, state)
        log_action(admin, post, state)
        actions_to_perform = 2

        Rake::Task['reviewables:migrate_akismet_reviews'].invoke
        reviewable = ReviewableAkismetPost.includes(:reviewable_histories).last
        reviewable_participants = reviewable.reviewable_histories.pluck(:created_by_id)

        assert_review_was_created_correctly(reviewable, state)
        expect(reviewable_participants).to eq [system_user.id, admin.id]
      end
    end

    it 'Migrates posts needing review and leaves them ready to be reviewed with the new API' do
      state = 'needs_review'
      DiscourseAkismet.move_to_state(post, state)
      actions_to_perform = 1

      Rake::Task['reviewables:migrate_akismet_reviews'].invoke
      reviewable = ReviewableAkismetPost.includes(:reviewable_histories).last
      reviewable_participants = reviewable.reviewable_histories.pluck(:created_by_id)

      assert_review_was_created_correctly(reviewable, state)
      expect(reviewable_participants).to eq [system_user.id]
    end

    it 'Migrates posts that were soft deleted and tag the new reviewable to reflect that' do
      action = 'confirmed_spam_deleted'
      DiscourseAkismet.move_to_state(post, 'confirmed_spam')
      log_action(admin, post, action)

      Rake::Task['reviewables:migrate_akismet_reviews'].invoke
      reviewable = ReviewableAkismetPost.last

      expect(reviewable.status).to eq reviewable_status_for(action)
    end

    def assert_review_was_created_correctly(reviewable, state)
      expect(reviewable.status).to eq reviewable_status_for(state)
      expect(reviewable.target_id).to eq post.id
      expect(reviewable.topic_id).to eq post.topic_id
      expect(reviewable.reviewable_by_moderator).to eq true
    end

    def reviewable_status_for(state)
      reviewable_states = Reviewable.statuses
      case state
      when 'confirmed_spam'
        reviewable_states[:approved]
      when 'confirmed_ham'
        reviewable_states[:rejected]
      when 'dismissed'
        reviewable_states[:ignored]
      when 'confirmed_spam_deleted'
        reviewable_states[:deleted]
      else
        reviewable_states[:pending]
      end
    end

    def log_action(admin, post, state)
      StaffActionLogger.new(admin).log_custom(state,
        post_id: post.id,
        topic_id: post.topic_id,
        created_at: post.created_at,
      )
    end
  end
end
