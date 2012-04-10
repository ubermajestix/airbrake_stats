class AirbrakeStats::Cache
  attr_reader :error_id
  def initialize(error_id)
    @error_id = error_id
  end

  def store(errors)
    File.open(filename, "w"){|f| f.write errors.to_yaml}
  end

  def load_errors
    if File.exists?(filename) && !expired?
      YAML.load_file(filename).map{|s| Map.new(s)}
    end
  end

  def filename
    "/tmp/airbrake_stats_#{error_id}.yml"
  end

  def expired?
    expires_in <= 0
  end

  def expires_in
    expires - (Time.now.to_i - File.mtime(filename).to_i)
  end

  def expires
    900
  end
end
