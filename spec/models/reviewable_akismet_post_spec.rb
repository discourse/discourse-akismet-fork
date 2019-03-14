require 'rails_helper'

describe ReviewableAkismetPost do
  let(:guardian) { Guardian.new }
  let(:reviewable) { ReviewableAkismetPost.new }

  describe '#build_actions' do
    (Reviewable.statuses.keys - [:pending]).each do |status|
      it 'Does not return available actions when the reviewable is no longer pending' do
        reviewable.status = Reviewable.statuses[status]
        an_action_id = :confirm_spam

        actions = reviewable_actions(guardian)

        expect(actions.to_a).to be_empty
      end
    end

    it 'Adds the confirm spam action' do
      expected_action_id = :confirm_spam

      actions = reviewable_actions(guardian)

      expect(actions.has?(expected_action_id)).to be true
    end

    it 'Adds the not spam action' do
      expected_action_id = :not_spam

      actions = reviewable_actions(guardian)

      expect(actions.has?(expected_action_id)).to be true
    end

    it 'Adds the dismiss action' do
      expected_action_id = :dismiss

      actions = reviewable_actions(guardian)

      expect(actions.has?(expected_action_id)).to be true
    end

    it 'Adds the confirm delete action' do
      admin = Fabricate(:admin)
      guardian = Guardian.new(admin)
      expected_action_id = :confirm_delete

      actions = reviewable_actions(guardian)

      expect(actions.has?(expected_action_id)).to be true
    end

    it 'Excludes the confirm delete action when the user is not an staff member' do
      expected_action_id = :confirm_delete

      actions = reviewable_actions(guardian)

      expect(actions.has?(expected_action_id)).to be false
    end

    def reviewable_actions(guardian)
      actions = Reviewable::Actions.new(reviewable, guardian, {})
      reviewable.build_actions(actions, guardian, {})

      actions
    end
  end

  describe 'Performing actions on reviewable' do
    let(:post) { Fabricate(:post) }
    let(:admin) { Fabricate(:admin) }
    let(:reviewable) { described_class.needs_review!(target: post, created_by: admin) }

    shared_examples 'It logs actions in the staff actions logger' do
      it 'Creates a UserHistory that reflects the action taken' do
        reviewable.perform admin, action

        admin_last_action = UserHistory.find_by(post: post)

        assert_history_reflects_action(admin_last_action, admin, post, action_name)
      end

      def assert_history_reflects_action(action, admin, post, action_name)
        expect(action.custom_type).to eq action_name
        expect(action.post_id).to eq post.id
        expect(action.topic_id).to eq post.topic_id
      end
    end

    describe '#perform_confirm_spam' do
      let(:action) { :confirm_spam }
      let(:action_name) { 'confirmed_spam' }

      it_behaves_like 'It logs actions in the staff actions logger'

      it 'Confirms spam and reviewable status is changed to approved' do
        DiscourseAkismet.expects(:move_to_state).with(post, 'confirmed_spam')

        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :approved
      end
    end

    describe '#perform_not_spam' do
      let(:action) { :not_spam }
      let(:action_name) { 'confirmed_ham' }

      it_behaves_like 'It logs actions in the staff actions logger'

      it 'Set post as clear and reviewable status is changed to rejected' do
        DiscourseAkismet.expects(:move_to_state).with(post, 'confirmed_ham')

        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :rejected
      end

      it 'Sends feedback to Akismet since post was not spam' do
        Jobs.stubs(:enqueue).with(Not(equals(:update_akismet_status)), anything)

        Jobs.expects(:enqueue).with(:update_akismet_status, post_id: post.id, status: 'ham')

        reviewable.perform admin, action
      end

      it 'Recovers the post' do
        post.deleted_at = 3.minutes.ago
        post.deleted_by = admin

        reviewable.perform admin, action

        expect(post.deleted_at).to be_nil
        expect(post.deleted_by).to be_nil
      end

      it 'Does not try to recover the post if it was already recovered' do
        post.deleted_at = nil
        event_triggered = false

        DiscourseEvent.on(:post_recovered) { event_triggered = true }
        reviewable.perform admin, action

        expect(event_triggered).to eq false
      end
    end

    describe '#perform_dismiss' do
      let(:action) { :dismiss }
      let(:action_name) { 'dismissed' }

      it_behaves_like 'It logs actions in the staff actions logger'

      it 'Set post as dismissed and reviewable status is changed to ignored' do
        DiscourseAkismet.expects(:move_to_state).with(post, 'dismissed')

        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :ignored
      end
    end

    describe '#perform_confirm_delete' do
      let(:action) { :confirm_delete }
      let(:action_name) { 'confirmed_spam_deleted' }

      it_behaves_like 'It logs actions in the staff actions logger'

      it 'Confirms spam and reviewable status is changed to deleted' do
        DiscourseAkismet.expects(:move_to_state).with(post, 'confirmed_spam')

        result = reviewable.perform admin, action

        expect(result.transition_to).to eq :deleted
      end

      it 'Deletes the user' do
        reviewable.perform admin, action

        expect(post.reload.user).to be_nil
      end

      it 'Does not delete the user when it cannot be deleted' do
        post.user = admin

        reviewable.perform admin, action

        expect(post.reload.user).to be_present
      end
    end
  end
end
