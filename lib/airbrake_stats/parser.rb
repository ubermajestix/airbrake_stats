class AirbrakeStats::Parser
  attr_accessor :error_id
  attr_reader :max_pages
  attr_reader :cache
  class Error < StandardError; end;

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
      id = parse_xml(notice, 'id')
      url = parse_xml(notice, 'url')
      format = parse_xml(notice, 'format')
      path = parse_xml(notice, 'request-path')
      controller = parse_xml(notice, 'controller')
      error_message = parse_xml(notice, 'error-message')
      action = parse_xml(notice, 'action')
      controller = "#{controller}##{action}"
      #next unless url && agent && path && format
      Map.new(id: id, path: path, format: format, error_message: error_message, url: url, agent: agent, controller: controller )
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
    @url ||= "https://#{ENV['AIRBRAKE_HOST']}.airbrake.io/errors/#{error_id}"
  end

  def parse(path, page = nil)
    params = "?auth_token=#{ENV['AIRBRAKE_TOKEN']}"
    params << "&page=#{page}" if page
    # puts "#{url}#{path}.xml#{params}"
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