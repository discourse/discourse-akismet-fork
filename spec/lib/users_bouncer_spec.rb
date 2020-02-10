# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DiscourseAkismet::UsersBouncer do

  let(:user) do
    Fabricate(:user, trust_level: TrustLevel[0]).tap do |user|
      user.user_profile.bio_raw = "I am batman"
      user.user_auth_token_logs = [UserAuthTokenLog.new(client_ip: '127.0.0.1', action: 'an_action')]
    end
  end

  before do
    SiteSetting.akismet_enabled = true
    SiteSetting.akismet_review_users = true
    SiteSetting.akismet_api_key = 'fake_key'
  end

  describe "#should_check?" do

    it "returns false when setting is disabled" do
      SiteSetting.akismet_review_users = false

      expect(subject.should_check?(user)).to eq(false)
    end

    it "returns false when user is higher than TL0" do
      user.trust_level = TrustLevel[1]

      expect(subject.should_check?(user)).to eq(false)
    end

    it "returns false when user has no bio" do
      user.user_profile.bio_raw = ""

      expect(subject.should_check?(user)).to eq(false)
    end

    it "returns false if a Reviewable already exists for that user" do
      ReviewableUser.create_for(user)

      expect(subject.should_check?(user)).to eq(false)
    end

    it "returns true for TL0 with a bio" do
      expect(subject.should_check?(user)).to eq(true)
    end

    it "returns false when there are no auth token logs for that user" do
      user.user_auth_token_logs = []

      expect(subject.should_check?(user)).to eq(false)
    end

    it "returns false when there client ip is not present" do
      user.user_auth_token_logs = [UserAuthTokenLog.new(client_ip: nil, action: 'an_action')]

      expect(subject.should_check?(user)).to eq(false)
    end
  end

  describe "#enqueue_for_check" do
    it "enqueues a job when user is TL0 and bio is present" do
      expect {
        subject.enqueue_for_check(user)
      }.to change {
        Jobs::CheckUsersForSpam.jobs.size
      }.by(1)
    end
  end

  describe "#check_user" do
    it "does not create a Reviewable if Akismet says it's not spam" do
      expect {
        subject.perform_check(akismet(is_spam: false), user)
      }.to_not change {
        ReviewableAkismetUser.count
      }
    end

    it "creates a Reviewable if Akismet says it's spam" do
      expect {
        subject.perform_check(akismet(is_spam: true), user)
      }.to change {
        ReviewableAkismetUser.count
      }.by(1)

      reviewable = ReviewableAkismetUser.last
      expect(reviewable.target).to eq(user)
      expect(reviewable.created_by).to eq(Discourse.system_user)
      expect(reviewable.reviewable_by_moderator).to eq(true)
      expect(reviewable.payload['username']).to eq(user.username)
      expect(reviewable.payload['name']).to eq(user.name)
      expect(reviewable.payload['email']).to eq(user.email)
      expect(reviewable.payload['bio']).to eq(user.user_profile.bio_raw)

      score = ReviewableScore.last
      expect(score.user).to eq(Discourse.system_user)
      expect(score.reviewable_score_type).to eq(PostActionType.types[:spam])
      expect(score.take_action_bonus).to eq(0)
    end

    def akismet(is_spam:)
      mock("Akismet::Client").tap do |client|
        client.expects(:comment_check).returns(is_spam)
      end
    end
  end

  describe ".to_check" do
    it 'returns users in new state and ignore the rest' do
      user_to_check = Fabricate(:user, trust_level: 0)
      user_to_ignore = Fabricate(:user, trust_level: 0)
      subject.move_to_state(user_to_check, 'new')
      subject.move_to_state(user_to_ignore, 'confirmed_ham')

      expect(described_class.to_check).to contain_exactly(user_to_check)
    end

    it 'only checks TL0 users' do
      user = Fabricate(:user, trust_level: 1)
      subject.move_to_state(user, 'new')

      expect(described_class.to_check).to be_empty
    end

    it 're-checks skipped users' do
      user = Fabricate(:user, trust_level: 0)
      subject.move_to_state(user, 'skipped')

      expect(described_class.to_check).to contain_exactly(user)
    end

    it 'does not check skipped users created more than 24 hours ago' do
      user = Fabricate(:user, trust_level: 0, created_at: 2.days.ago)
      subject.move_to_state(user, 'skipped')

      expect(described_class.to_check).to be_empty
    end
  end
end
