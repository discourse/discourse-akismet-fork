# frozen_string_literal: true

require 'rails_helper'

describe Akismet do
  let(:client) { Akismet::Client.new(api_key: 'somekey', base_url: 'someurl') }
  let(:mock_response) { Struct.new(:status, :body, :headers) }

  let(:post_args) do
    {
      content_type: "forum-post",
      permalink: "http://test.localhost/t/this-is-a-test-topic-49/1889/1",
      comment_author: "bruce106",
      comment_content: "This is a test topic 49\n\nHello world",
      comment_author_email: "bruce106@wayne.com"
    }
  end

  describe "#comment_check" do
    it "should return true if the post is spam" do
      Excon.expects(:post).returns(mock_response.new(200, 'true'))

      expect(client.comment_check(post_args)).to eq(true)
    end

    it "should return false if the post is not spam" do
      Excon.expects(:post).returns(mock_response.new(200, 'false'))

      expect(client.comment_check(post_args)).to eq(false)
    end

    it "should raise an error with the right message if response is not valid" do
      Excon.expects(:post).returns(mock_response.new(
        200,
        'Some unknown error',
        "#{Akismet::Client::DEBUG_HEADER}" => 'Empty "Blog" value'
      ))

      expect {
        client.comment_check(post_args)
      }.to raise_error(Akismet::Error, 'Empty "Blog" value')

      Excon.expects(:post).returns(mock_response.new(200, 'Some unknown error', {}))

      expect {
        client.comment_check(post_args)
      }.to raise_error(Akismet::Error, Akismet::Client::UNKNOWN_ERROR_MESSAGE)
    end
  end

  describe '#submit_feedback' do
    shared_examples 'sends feedback to Akismet and handles the response' do
      it "should return true" do
        Excon.expects(:post).returns(mock_response.new(200, Akismet::Client::VALID_SUBMIT_RESPONSE))

        expect(client.submit_feedback(feedback, post_args)).to eq(true)
      end

      it "should raise the right error" do
        Excon.expects(:post).returns(mock_response.new(200, "Some error"))

        expect {
          client.submit_feedback(feedback, post_args)
        }.to raise_error(Akismet::Error, Akismet::Client::UNKNOWN_ERROR_MESSAGE)
      end
    end

    context 'spam' do
      let(:feedback) { 'spam' }
      it_behaves_like 'sends feedback to Akismet and handles the response'
    end

    context 'ham' do
      let(:feedback) { 'ham' }
      it_behaves_like 'sends feedback to Akismet and handles the response'
    end
  end
end
