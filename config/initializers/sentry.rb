# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = 'https://22dfb14ef95e4f5596b4c8d439b770c0@o256076.ingest.sentry.io/6298520'
  config.breadcrumbs_logger = %i[active_support_logger http_logger]

  # Set tracesSampleRate to 1.0 to capture 100%
  # of transactions for performance monitoring.
  # We recommend adjusting this value in production
  # config.traces_sample_rate = 0.01
  # or
  # config.traces_sampler = lambda do |context|
  #   true
  # end
  config.traces_sampler = lambda do |sampling_context|
    # if this is the continuation of a trace, just use that decision (rate controlled by the caller)
    next sampling_context[:parent_sampled] unless sampling_context[:parent_sampled].nil?

    # transaction_context is the transaction object in hash form
    # keep in mind that sampling happens right after the transaction is initialized
    # for example, at the beginning of the request
    transaction_context = sampling_context[:transaction_context]

    # transaction_context helps you sample transactions with more sophistication
    # for example, you can provide different sample rates based on the operation or name
    case transaction_context[:op]
    when /delayed_job/
      contexts = Sentry.get_current_scope.contexts
      job_class = contexts.dig(:'Active-Job', :job_class)
      attempts = contexts.dig(:'Delayed-Job', :attempts)
      max_attempts = begin
        job_class.safe_constantize&.new&.max_attempts
      rescue StandardError
        25
      end

      # Don't trace on all attempts
      [0, 2, 5, 10, 20, max_attempts].include?(attempts)
    else # rails requests
      0.01
    end
  end

  config.delayed_job.report_after_job_retries = false # don't wait for all attempts before reporting
end
