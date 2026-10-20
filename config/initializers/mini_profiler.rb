# The profiler badge is handy but noisy and adds a little time to every request.
# It stays out of sight until you add ?pp=enable to a URL.
if defined?(Rack::MiniProfiler) && Rails.env.development?
  Rack::MiniProfiler.config.start_hidden = true
end
