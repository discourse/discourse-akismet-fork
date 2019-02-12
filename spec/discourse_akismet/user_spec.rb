require 'rails_helper'

describe DiscourseAkismet::User do
  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true

    user_profile = user.user_profile
    user_profile.bio_raw = random_bio
    user_profile.save
  end

  let(:user) { Fabricate(:newuser) }

  let(:random_bio) { 'random profile' }

  it 'checks job is enqueued on user create' do
    user
    jobs = Jobs::CheckAkismetUser.jobs.select do |job|
      job['class'] == 'Jobs::CheckAkismetUser' && job['args'] &&
      job['args'].select { |arg| arg['user_id'] == user.id }.count == 1
    end

    expect(jobs.count).to eq(1)
  end

  describe '#args' do

    it 'should return args for a user' do
      result = described_class.new(user).args

      expect(result[:comment_content]).to eq(random_bio)
      expect(result[:comment_author]).to eq(user.username)
      expect(result[:permalink]).to eq("#{Discourse.base_url}/u/#{user.username}")
      expect(result[:content_type]).to eq('user-tl0')
      expect(result[:comment_author_email]).to eq(user.email)
    end

    it 'should return nil in email when akismet akismet_transmit_email is false' do
      SiteSetting.akismet_transmit_email = false

      result = described_class.new(user).args

      expect(result[:comment_author_email]).to be_nil
    end

  end

  describe '#move_to_state' do

    it 'moves user to new state' do
      described_class.new(user).move_to_state(DiscourseAkismet::NEEDS_REVIEW)

      akismet_state = UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY)

      expect(akismet_state.count).to eq(1)
      expect(akismet_state.last.value).to eq(DiscourseAkismet::NEEDS_REVIEW)
    end

    it 'does not move user to new state if setting is disabled or user is nil' do
      SiteSetting.akismet_enabled = false
      described_class.new(user).move_to_state(DiscourseAkismet::NEEDS_REVIEW)

      akismet_state = UserCustomField.where(name: DiscourseAkismet::AKISMET_STATE_KEY, user_id: user.id)
      expect(akismet_state.count).to eq(0)

      SiteSetting.akismet_enabled = true
      described_class.new(nil).move_to_state(DiscourseAkismet::NEEDS_REVIEW)
      expect(akismet_state.reload.count).to eq(0)
    end

  end

  describe '#should_check_for_spam' do

    it 'does not check when user is blank' do
      expect(described_class.new(nil).should_check_for_spam?).to eq(false)
    end

    it 'checks when user is level 0' do
      expect(described_class.new(user).should_check_for_spam?).to eq(true)
    end

    it 'does not check when site setting is disabled' do
      SiteSetting.akismet_enabled = false

      expect(described_class.new(user).should_check_for_spam?).to eq(false)

      SiteSetting.akismet_enabled = true
      SiteSetting.akismet_api_key = nil
      expect(described_class.new(user).should_check_for_spam?).to eq(false)
    end

    it 'does not check when user trust level is not 0' do
      user.trust_level = 1
      user.save

      expect(described_class.new(user).should_check_for_spam?).to eq(false)
    end

    it 'returns false when user bio is empty' do
      user_profile = user.user_profile
      user_profile.bio_raw = nil
      user_profile.save

      expect(described_class.new(user).should_check_for_spam?).to eq(false)
    end

  end

  describe '.to_check' do

    it 'returns tl0 user who are not checked for spam' do
      user

      result = described_class.to_check
      expect(result.where(id: user.id).count).to eq(1)

      user.upsert_custom_fields(DiscourseAkismet::AKISMET_STATE_KEY => DiscourseAkismet::NEEDS_REVIEW)
      result = described_class.to_check
      expect(result.where(id: user.id).count).to eq(0)
    end

  end

end
