require 'rails_helper'

describe Jobs::CheckForSpamUsers do

  let(:user) { Fabricate(:newuser) }
  let(:mock_response) { Struct.new(:status, :body, :headers) }

  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true

    user_profile = user.user_profile
    user_profile.bio_raw = 'random bio'
    user_profile.save
  end

  it 'changes akismet_status of tl0 user' do
    Excon.expects(:post).returns(mock_response.new(200, 'true'))
    user

    described_class.new.execute

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to eq(DiscourseAkismet::NEEDS_REVIEW)
  end

  it 'does not change status of >tl0 user' do
    user.trust_level = 1
    user.save

    described_class.new.execute

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to be_nil

  end

end
