# frozen_string_literal: true

# frozen_string_literal

require 'rails_helper'

RSpec.describe DiscourseAkismet::UsersBouncer do
  describe '#enqueue_for_check' do
    before { SiteSetting.akismet_review_users = true }

    let(:user) do
      Fabricate.build(:user, user_profile: Fabricate.build(:user_profile), trust_level: TrustLevel[0])
    end

    it 'does not enqueue for check if user trust level is higher than 0' do
      user.trust_level = TrustLevel[1]

      queued_jobs_for_check(user, 0)
    end

    it 'enqueues the user when trust level is higher than zero and bio is present' do
      user.user_profile.bio_raw = "Let's spam"

      queued_jobs_for_check(user, 1)
    end

    it 'does not enqueue for check if user bio is empty' do
      user.user_profile.bio_raw = ''

      queued_jobs_for_check(user, 0)
    end

    it 'xxxxxxx' do
      SiteSetting.akismet_review_users = false
      user.user_profile.bio_raw = "Let's spam"

      queued_jobs_for_check(user, 0)
    end

    def queued_jobs_for_check(to_check, expected_queued_jobs)
      expect {
        subject.enqueue_for_check(to_check)
      }.to change(Jobs::CheckUsersForSpam.jobs, :size).by(expected_queued_jobs)
    end
  end

  describe '#check_user', if: defined?(Reviewable) do
    let(:user) do
      Fabricate(:user, trust_level: TrustLevel[0])
    end

    before { UserAuthToken.generate!(user_id: user.id) }

    it "does not create a reviewable if akismet says it's not spam" do
      should_find_spam = false

      subject.check_user(build_client(should_find_spam), user)

      expect(ReviewableAkismetUser.count).to be_zero
    end

    it "creates a reviewable if akismet says it's spam" do
      should_find_spam = true

      subject.check_user(build_client(should_find_spam), user)
      created_reviewable = ReviewableAkismetUser.last
      created_score = ReviewableScore.last

      assert_reviewable_was_created_correctly(created_reviewable)
      assert_score_was_created(created_score)
    end

    def assert_reviewable_was_created_correctly(reviewable)
      expect(reviewable.target).to eq user
      expect(reviewable.created_by).to eq Discourse.system_user
      expect(reviewable.reviewable_by_moderator).to eq true
      expect(reviewable.payload['username']).to eq user.username
      expect(reviewable.payload['name']).to eq user.name
      expect(reviewable.payload['email']).to eq user.email
      expect(reviewable.payload['bio']).to eq user.user_profile.bio_raw
    end

    def assert_score_was_created(score)
      expect(score.user).to eq Discourse.system_user
      expect(score.reviewable_score_type).to eq PostActionType.types[:spam]
      expect(score.take_action_bonus).to be_zero
    end

    def build_client(detect_spam)
      mock('Akismet::Client').tap do |client|
        client.expects(:comment_check).returns(detect_spam)
      end
    end
  end

  describe '#submit_feedback' do
    let(:user) { Fabricate(:user) }

    it 'validates that the status is valid' do
      non_valid_status = 'clear'
      client = mock('Akismet::Client')

      expect do
        described_class.new.submit_feedback(client, non_valid_status, user)
      end.to raise_error(Discourse::InvalidParameters)
    end
  end
end
