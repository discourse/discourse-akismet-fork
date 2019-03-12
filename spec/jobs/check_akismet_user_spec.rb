require 'rails_helper'

describe Jobs::CheckAkismetUser do

  let(:user) { Fabricate(:newuser) }

  let(:mock_response) { Struct.new(:status, :body, :headers) }

  let(:akismet_url_regex) { /rest.akismet.com/ }

  before do
    SiteSetting.akismet_api_key = 'not_a_real_key'
    SiteSetting.akismet_enabled = true

    user_profile = user.user_profile
    user_profile.bio_raw = 'random bio'
    user_profile.save
  end

  it 'moves to needs_review for tl0 spam user' do
    stub_request(:post, akismet_url_regex).
        to_return(status: 200, body: "true", headers: {})

    described_class.new.execute({user_id: user.id, profile_content: user.user_profile.bio_raw})

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to eq(DiscourseAkismet::NEEDS_REVIEW)
  end

  it 'moves to checked for tl0 user who is not selected as spam' do
    stub_request(:post, akismet_url_regex).
        to_return(status: 200, body: "false", headers: {})

    described_class.new.execute({user_id: user.id, profile_content: user.user_profile.bio_raw})
    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to eq(DiscourseAkismet::CHECKED)
  end

  it 'does not check spam for user above tl0' do
    user.trust_level = 1
    user.save

    described_class.new.execute({user_id: user.id, profile_content: user.user_profile.bio_raw})

    expect(user.custom_fields[DiscourseAkismet::AKISMET_STATE_KEY]).to be_nil
  end

end
