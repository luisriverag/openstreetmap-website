require "test_helper"

class NoteCommentTest < ActiveSupport::TestCase
  def test_event_valid
    ok = %w[opened closed reopened commented hidden]
    bad = %w[expropriated fubared]

    ok.each do |event|
      note_comment = create(:note_comment)
      note_comment.event = event
      assert_predicate note_comment, :valid?, "#{event} is invalid, when it should be"
    end

    bad.each do |event|
      note_comment = create(:note_comment)
      note_comment.event = event
      assert_not_predicate note_comment, :valid?, "#{event} is valid when it shouldn't be"
    end
  end

  def test_body_valid
    ok = %W[Name vergrößern foo\nbar
            ルシステムにも対応します 輕觸搖晃的遊戲]
    bad = ["foo\x00bar", "foo\x08bar", "foo\x1fbar", "foo\x7fbar",
           "foo\ufffebar", "foo\uffffbar"]

    ok.each do |body|
      note_comment = create(:note_comment)
      note_comment.body = body
      assert_predicate note_comment, :valid?, "#{body} is invalid, when it should be"
    end

    bad.each do |body|
      note_comment = create(:note_comment)
      note_comment.body = body
      assert_not_predicate note_comment, :valid?, "#{body} is valid when it shouldn't be"
    end
  end
end
