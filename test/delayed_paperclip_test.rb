require 'test_helper'
require 'delayed_job'
Delayed::Worker.backend = :active_record

class DelayedPaperclipTest < Test::Unit::TestCase
  def setup
    super

    build_delayed_jobs
    reset_dummy
  end

  def test_enqueue_job_if_source_changed
    @dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")

    original_job_count = Delayed::Job.count
    @dummy.save

    assert_equal original_job_count + 1, Delayed::Job.count
  end

  def test_perform_job
    @dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")
    Paperclip::Attachment.any_instance.expects(:reprocess!)

    @dummy.save!
    Delayed::Job.last.payload_object.perform
  end

  def test_processing_column_kept_intact
    @dummy = reset_dummy(true)

    Paperclip::Attachment.any_instance.stubs(:reprocess!).raises(StandardError.new('oops'))

    @dummy.save!
    assert @dummy.image_processing?
    Delayed::Worker.new.work_off
    assert @dummy.reload.image_processing?
  end

  def test_after_callback_is_functional
    @dummy_class.send(:define_method, :done_processing) { puts 'done' }
    @dummy_class.after_image_post_process :done_processing
    Dummy.any_instance.expects(:done_processing)

    @dummy.save!
    DelayedPaperclip::Jobs::DelayedJob.new(@dummy.class.name, @dummy.id, :image).perform
  end

  def test_processing_true_when_new_image_added
    @dummy = reset_dummy(true)

    assert !@dummy.image_processing?
    assert @dummy.new_record?
    @dummy.save!
    assert @dummy.reload.image_processing?
  end

  def test_processed_true_when_delayed_jobs_completed
    @dummy = reset_dummy(true)
    @dummy.save!

    Delayed::Worker.new.work_off

    @dummy.reload
    assert !@dummy.image_processing?
  end

  def test_unprocessed_image_returns_missing_url
    @dummy = reset_dummy(true)
    @dummy.save!

    assert_equal "/images/original/missing.png", @dummy.image.url

    Delayed::Job.first.invoke_job

    @dummy.reload
    assert_match(/\/system\/images\/1\/original\/12k.png/, @dummy.image.url)
  end

  def test_original_url_when_no_processing_column
    @dummy = reset_dummy(false)
    @dummy.save!

    assert_match(/\/system\/images\/1\/original\/12k.png/, @dummy.image.url)
  end

  def test_original_url_if_image_changed
    @dummy.image = File.open("#{RAILS_ROOT}/test/fixtures/12k.png")
    @dummy.save!

    assert_match(/system\/images\/.*original.*/, @dummy.image.url)
  end

  def test_missing_url_if_image_hasnt_changed
    @dummy = reset_dummy(true)
    @dummy.save!

    assert_match(/images\/.*missing.*/, @dummy.image.url)
  end

  def test_should_not_blow_up_if_dsl_unused
    reset_class "Dummy", false
    @dummy = Dummy.new(:image => File.open("#{RAILS_ROOT}/test/fixtures/12k.png"))

    assert @dummy.image.url
  end
end
