# TODO cleanup this class, Parser is kind of a bad name.
# I'm thinking the http stuff could go in its own class
# and the xml parsing can still happen here.
#
# TODO Also these methods need more documentation. I think 
# some refactoring will naturally fallout of writing
# docs.
class AirbrakeStats::Parser
  attr_accessor :error_id
  attr_reader :max_pages
  attr_reader :cache

  class AirbrakeStats::Error < StandardError; end;

  def initialize(error_id)
    @error_id = error_id
    @max_pages = Integer((ENV['MAX_PAGES'] || 10))
    @cache = AirbrakeStats::Cache.new(error_id)
  end

  def similar_errors

    return @similar_errors if @similar_errors
    if @similar_errors = cache.load_errors
      puts "Loaded cached errors from #{cache.filename} (will expire in #{cache.expires_in/60} minutes)"
      return @similar_errors
    end
    @similar_errors = notices_xml.map do |notice|
      agent = notice.search('http-user-agent').first
      if agent
        # TODO better user agent parsing, but this is good enough to see if
        # errors are caused by bots or "humans"
        agent = "#{agent[2]} #{agent[3]}" 
      end
      # TODO refactor this crap
      id = parse_xml(notice, 'id')
      url = parse_xml(notice, 'url')
      #format = parse_xml(otice, 'format')
      format = parse_xml(notice, 'action-dispatch-request-formats')
      path = parse_xml(notice, 'request-path')
      controller = parse_xml(notice, 'controller')
      error_message = parse_xml(notice, 'error-message')
      action = parse_xml(notice, 'action')
      controller = "#{controller}##{action}"
      #TODO build up the params hash (excluding action and controller) from the params node.
      #next unless url && agent && path && format
      host = parse_xml(notice, 'http-host')
      accept = parse_xml(notice, 'http-accept')
      referer = parse_xml(notice, 'http-referer')
      orig_referer = parse_xml(notice, 'orig-referrer')
      created_at = parse_xml(notice, 'created-at')
      day = created_at ? Date.parse(created_at).to_s : nil
      #next unless url && agent && path && format
      Map.new(id: id,
              day: day,
              path: path,
              format: format,
              error_message: error_message,
              url: url, 
              agent: agent, 
              controller: controller, 
              host: host, 
              accept: accept,
              referer: referer,
              orig_referer: orig_referer )
    end.compact
    cache.store(@similar_errors)
    if @similar_errors.empty?
      puts "no notices had any data"
      puts notices_xml.map{|n| n.search('error-message').first.text}.uniq
    else
      cache.store(@similar_errors)
    end
    @similar_errors
  end

  # Just grab and parse /errors/#{error_id}.xml
  def error
    @error ||= parse('')
  end

  def parse_xml(notice, element)
    node = notice.search(element).first
    node.text if node 
  end

  # Count up the occurance of either:
  # - path
  # - format
  # - url
  # - agent
  # Will return an Array of Maps sorted from lowest to highest occurance
  def stats(method)
    stats = Hash.new(0)
    similar_errors.each{|n| stats[n[method]] += 1}
    stats = stats.map do |p| 
      h = {total: p.last} 
      h[method] = p.first
      Map.new(h)
    end.sort_by(&:total)
  end

  # Integer representing the ammount of  pages of errors. Based on Aibrake's docs
  # that state they return 30 errors per request, so we divide the total number of 
  # errors by 30 to get our number of pages
  def page_count
    @page_count = notices_count/30 + 1
    @page_count = max_pages if @page_count > max_pages
    @page_count
  end

  def max_errors
    page_count * 30
  end

  # An Integer representing the number of other similar errors
  def notices_count
    @notices_count ||= error.search('notices-count').first.text.to_i
  end

  private

  def similar_error_ids
    return @similar_error_ids if @similar_error_ids
    @similar_error_ids = []
    puts "Getting #{page_count} pages of errors."
    page_count.times do |page|
      page += 1
      errors = parse('/notices', page)
      @similar_error_ids << errors.search('id').map(&:text)
    end
    @similar_error_ids.flatten!
    if @similar_error_ids.length == max_errors
      puts "Found #{notices_count} similar errors but only using the #{max_errors} most recent."
    else
      puts "Found #{notices_count} similar errors."
    end
    @similar_error_ids
  end

  def notices_xml
    similar_error_ids
    notices_xml = AirbrakeStats::Queue.new
    puts "Downloading errors..."
    threads = []
    # TODO sometimes this craps out. Ususally when we ask for pages > 20
    similar_error_ids.each_slice(4) do |slice|
      threads << Thread.new(slice) do |ids|
        ids.each_with_index do |id, index|
          # print "#{index}/#{notices_count}\r"; $stdout.flush
          notices_xml << parse("/notices/#{id}")
        end
      end
    end
    threads.map(&:join)
    puts notices_xml.size
    notices_xml.to_a
  end

  def url
    @url ||= (ENV['AIRBRAKE_URL'] || "https://#{ENV['AIRBRAKE_HOST']}.airbrake.io/") + "errors/#{error_id}"
  end

  # TODO use a config object
  def token
    @token ||= ENV['AIRBRAKE_TOKEN']
    raise AirbrakeStats::Error.new('Please provide your api token') unless @token
    @token
  end
  

  def parse(path, page = nil)
    params = "?auth_token=#{token}"
    params << "&page=#{page}" if page
    #puts "#{url}#{path}.xml#{params}"
    # TODO sometimes this craps out. Ususally when we ask for pages > 20
    # Error: `sysread_nonblock': Resource temporarily unavailable (Errno::EAGAIN)
    # should put retry logic in here, i.e. keep trying to get a connection until you can
    response = Http.get("#{url}#{path}.xml#{params}", response: :object)
    parsed_response = Nokogiri::XML(response.body)
    if response.status == 200
      return parsed_response
    else
      error = parsed_response.search('error').first
      raise AirbrakeStats::Error.new("#{response.status}: #{error}")
    end
  end

end
