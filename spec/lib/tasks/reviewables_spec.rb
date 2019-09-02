# frozen_string_literal: true

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

        run_migration
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

        run_migration
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

      run_migration
      reviewable = ReviewableAkismetPost.includes(:reviewable_histories).last
      reviewable_participants = reviewable.reviewable_histories.pluck(:created_by_id)

      assert_review_was_created_correctly(reviewable, state)
      expect(reviewable_participants).to eq [system_user.id]
    end

    it 'Migrates posts that were soft deleted and tag the new reviewable to reflect that' do
      action = 'confirmed_spam_deleted'
      DiscourseAkismet.move_to_state(post, 'confirmed_spam')
      log_action(admin, post, action)

      run_migration
      reviewable = ReviewableAkismetPost.last

      expect(reviewable.status).to eq reviewable_status_for(action)
    end

    def assert_review_was_created_correctly(reviewable, state)
      expect(reviewable.status).to eq reviewable_status_for(state)
      expect(reviewable.target_id).to eq post.id
      expect(reviewable.topic_id).to eq post.topic_id
      expect(reviewable.reviewable_by_moderator).to eq true
      expect(reviewable.payload['post_cooked']).to eq post.cooked
    end

    describe 'Migrating scores' do
      let(:spam_type) { PostActionType.types[:spam] }
      let(:type_bonus) { PostActionType.where(id: spam_type).pluck(:score_bonus)[0] }

      it 'Creates a pending score for pending reviews' do
        state = 'needs_review'
        DiscourseAkismet.move_to_state(post, state)

        run_migration
        reviewable = ReviewableAkismetPost.includes(:reviewable_scores).last
        score = reviewable.reviewable_scores.last

        assert_score_was_create_correctly(score, reviewable, state)
        expect(score.reviewed_by).to be_nil
        expect(score.take_action_bonus).to be_zero
        expect(score.score).to eq ReviewableScore.user_flag_score(reviewable.created_by) + type_bonus
      end

      %w[dismissed confirmed_spam confirmed_ham].each do |state|
        it "Creates an score with take action bonus when migrating a review with state: #{state} " do
          expected_bonus = 5.0
          DiscourseAkismet.move_to_state(post, state)
          log_action(admin, post, state)

          run_migration
          reviewable = ReviewableAkismetPost.includes(:reviewable_scores).last
          score = reviewable.reviewable_scores.last

          assert_score_was_create_correctly(score, reviewable, state)
          expect(score.reviewed_by).to eq admin
          expect(score.take_action_bonus).to eq expected_bonus
          expect(score.score).to eq ReviewableScore.user_flag_score(reviewable.created_by) + type_bonus + expected_bonus
        end
      end

      def assert_score_was_create_correctly(score, reviewable, action)
        expect(score.user).to eq reviewable.created_by
        expect(score.status).to eq score_status_for(action)
        expect(score.reviewable_score_type).to eq spam_type
        expect(score.created_at).to eq reviewable.created_at
      end

      def score_status_for(action)
        case action
        when 'needs_review'
          ReviewableScore.statuses[:pending]
        when 'dismissed'
          ReviewableScore.statuses[:ignored]
        when 'confirmed_spam'
          ReviewableScore.statuses[:agreed]
        else
          ReviewableScore.statuses[:disagreed]
        end
      end

    end
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

  def run_migration
    Rake::Task['reviewables:migrate_akismet_reviews'].invoke
  end
end
