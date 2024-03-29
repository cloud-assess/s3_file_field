module S3FileField
  class S3Uploader  # :nodoc:
    attr_accessor :options

    def initialize(original_options = {})

      default_options = {
        access_key_id: S3FileField.config.access_key_id,
        secret_access_key: S3FileField.config.secret_access_key,
        bucket: S3FileField.config.bucket,
        acl: "public-read",
        expiration: 10.hours.from_now.utc.iso8601,
        max_file_size: max_file_size,
        conditions: [],
        key_starts_with: S3FileField.config.key_starts_with || 'uploads/',
        region: S3FileField.config.region || 'us-east-1',
        url: S3FileField.config.url,
        ssl: S3FileField.config.ssl,
        date: Time.now.utc.strftime("%Y%m%d"),
        timestamp: Time.now.utc.strftime("%Y%m%dT%H%M%SZ")
      }

      @key = original_options[:key]
      @original_options = original_options

      # Remove s3_file_field specific options from original options
      extracted_options = @original_options.extract!(*default_options.keys).
        reject { |k, v| v.nil? }

      @options = default_options.merge(extracted_options)

      def hostname
        if @options[:region] == "us-east-1"
          "#{@options[:bucket]}.s3.amazonaws.com"
        else
          "#{@options[:bucket]}.s3.#{@options[:region]}.amazonaws.com"
        end
      end

      unless @options[:access_key_id]
        raise Error.new("Please configure access_key_id option.")
      end

      unless @options[:secret_access_key]
        raise Error.new("Please configure secret_access_key option.")
      end

      if @options[:bucket].nil? && @options[:url].nil?
        raise Error.new("Please configure bucket name or url.")
      end
    end

    def field_options
      @original_options.merge(data: field_data_options)
    end

    def field_data_options
      {
        :url => @options[:url] || url,
        :key => @options[:key] || key,
        :acl => @options[:acl],
        :max_file_size => @options[:max_file_size] || max_file_size,
        :policy => policy,
        :amzAlgorithm => 'AWS4-HMAC-SHA256',
        :amzCredential => "#{@options[:access_key_id]}/#{@options[:date]}/#{@options[:region]}/s3/aws4_request",
        :amzDate => @options[:timestamp],
        :amzSignature => signature,
      }.merge(@original_options[:data] || {})
    end

    private

    def key
      @key ||= "#{@options[:key_starts_with]}{timestamp}-{unique_id}-#{SecureRandom.hex}/${filename}"
    end

    def url
      @options[:url] || "http#{@options[:ssl] ? 's' : ''}://#{hostname}/"
    end

    def policy
      Base64.encode64(policy_data.to_json).gsub("\n", '')
    end

    def policy_data
      {
        expiration: @options[:expiration],
        conditions: [
          ["starts-with", "$key", @options[:key_starts_with]],
          ["starts-with", "$x-requested-with", ""],
          ["content-length-range", 0, @options[:max_file_size]],
          ["starts-with","$Content-Type",""],
          {bucket: @options[:bucket]},
          {acl: @options[:acl]},
          {success_action_status: "201"},
          {'X-Amz-Algorithm' => 'AWS4-HMAC-SHA256'},
          {'X-Amz-Credential' => "#{@options[:access_key_id]}/#{@options[:date]}/#{@options[:region]}/s3/aws4_request"},
          {'X-Amz-Date' => @options[:timestamp]}
        ] + @options[:conditions]
      }
    end

    def signing_key
      #AWS Signature Version 4

      kDate    = OpenSSL::HMAC.digest('sha256', "AWS4" + @options[:secret_access_key], @options[:date])
      kRegion  = OpenSSL::HMAC.digest('sha256', kDate, @options[:region])
      kService = OpenSSL::HMAC.digest('sha256', kRegion, 's3')
      kSigning = OpenSSL::HMAC.digest('sha256', kService, "aws4_request")

      kSigning
    end

    def signature
      OpenSSL::HMAC.hexdigest('sha256', signing_key, policy)
    end

    def max_file_size
      1024.megabytes
    end
  end
end
