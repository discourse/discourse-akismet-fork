# frozen_string_literal: true

require 'rails_helper'

describe 'ReviewableAkismetUser' do
  let(:guardian) { Guardian.new }

  describe '#build_actions' do
    let(:reviewable) { ReviewableAkismetUser.new }

    it 'does not return available actions when the reviewable is no longer pending' do
      available_actions = (Reviewable.statuses.keys - [:pending]).reduce([]) do |actions, status|
        reviewable.status = Reviewable.statuses[status]
        an_action_id = :not_spam

        actions.concat reviewable_actions(guardian).to_a
      end

      expect(available_actions).to be_empty
    end

    it 'adds the not spam action' do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:not_spam)).to be true
    end

    it 'adds the confirm delete action' do
      admin = Fabricate(:admin)
      guardian = Guardian.new(admin)

      actions = reviewable_actions(guardian)

      expect(actions.has?(:reject_user_delete)).to be true

      expect(actions.to_a.
        find { |a| a.id == :reject_user_delete }.button_class).
        to eq("btn-danger")
    end

    it 'excludes the confirm delete action when the user is not an staff member' do
      actions = reviewable_actions(guardian)

      expect(actions.has?(:perform_reject_user_delete)).to be false
    end

    def reviewable_actions(guardian)
      actions = Reviewable::Actions.new(reviewable, guardian, {})
      reviewable.build_actions(actions, guardian, {})

      actions
    end
  end

  describe 'performing actions on reviewable' do
    let(:admin) { Fabricate(:admin) }
    let(:user) { Fabricate(:user) }
    let(:reviewable) { ReviewableAkismetUser.needs_review!(target: user, created_by: admin) }

    before { UserAuthToken.generate!(user_id: user.id) }

    shared_examples 'it logs actions in the staff actions logger' do
      it 'creates a UserHistory that reflects the action taken' do
        reviewable.perform admin, action

        admin_last_action = UserHistory.find_by!(acting_user_id: admin)

        assert_history_reflects_action(admin_last_action, admin, action_name)
      end

      def assert_history_reflects_action(action, admin, action_name)
        expect(action.custom_type).to eq action_name
        expect(action.acting_user).to eq admin
      end

      it 'returns necessary information to update reviewable creator user stats' do
        result = reviewable.perform admin, action

        update_flag_stats = result.update_flag_stats

        expect(update_flag_stats[:status]).to eq flag_stat_status
        expect(update_flag_stats[:user_ids]).to match_array [reviewable.created_by_id]
      end
    end

    shared_examples 'it submits feedback to Akismet' do
      it 'queues a job to submit feedback' do
        expect {
          reviewable.perform admin, action
        }.to change(Jobs::UpdateAkismetStatus.jobs, :size).by(1)
      end
    end

    describe '#perform_not_spam' do
      let(:action) { :not_spam }
      let(:action_name) { 'confirmed_ham' }
      let(:flag_stat_status) { :disagreed }

      it_behaves_like 'it logs actions in the staff actions logger'
      it_behaves_like 'it submits feedback to Akismet'

      it 'sets post as clear and reviewable status is changed to rejected' do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :rejected
      end
    end

    describe '#perform_reject_user_delete' do
      let(:action) { :reject_user_delete }
      let(:action_name) { 'confirmed_spam_deleted' }
      let(:flag_stat_status) { :agreed }

      it_behaves_like 'it logs actions in the staff actions logger'
      it_behaves_like 'it submits feedback to Akismet'

      it 'confirms spam and reviewable status is changed to deleted' do
        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :deleted
      end

      it 'deletes the user' do
        reviewable.perform admin, action

        expect { user.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'deleting existing flagged posts for a flagged user' do
    let(:admin) { Fabricate(:admin) }
    let(:user) { Fabricate(:user) }
    let(:reviewable) { ReviewableAkismetUser.needs_review!(target: user, created_by: admin) }

    before do
      UserAuthToken.generate!(user_id: user.id)
    end

    it 'queues a job to approve existing Akismet flagged posts' do
      expect { reviewable.perform(admin, :reject_user_delete) }.to change(Jobs::ConfirmAkismetFlaggedPosts.jobs, :size).by(1)
    end

    it 'approved flagged posts by the flagged user' do
      flagged_post = Fabricate(:post, user: user)
      flagged_post_reviewable = ReviewableFlaggedPost.needs_review!(target: flagged_post, created_by: admin)

      reviewable.perform admin, :reject_user_delete

      expect(flagged_post_reviewable.reload.status).to eq(Reviewable.statuses[:approved])
    end
  end
end
