#= require jquery-fileupload/basic
#= require jquery-fileupload/vendor/tmpl

jQuery.fn.S3FileField = (options) ->

  options = {} unless options?

  # support multiple elements
  if @length > 1
    @each -> $(this).S3Uploader options if @length > 1
    return this

  $this = this

  extractOption = (key) ->
    extracted = options[key]
    delete options[key]
    extracted

  getFormData = (data, form) ->
    formData = undefined
    return data(form) if typeof data is "function"
    return data if $.isArray(data)
    if $.type(data) is "object"
      formData = []
      $.each data, (name, value) ->
        formData.push
          name: name
          value: value
      return formData
    return []

  url = extractOption('url')
  add = extractOption('add')
  done = extractOption('done')
  fail = extractOption('fail')
  extraFormData = extractOption('formData')

  delete options['paramName']
  delete options['singleFileUploads']

  finalFormData = {}

  settings =
    # File input name must be "file"
    paramName: 'file'

    # S3 doesn't support multiple file uploads
    singleFileUploads: true

    # We don't want to send it to default form url
    url: url || $this.data('url')

    # For IE <= 9 force iframe transport
    forceIframeTransport: do ->
      userAgent = navigator.userAgent.toLowerCase()
      msie = /msie/.test( userAgent ) && !/opera/.test( userAgent )
      msie_version = parseInt((userAgent.match( /.+(?:rv|it|ra|ie)[\/: ]([\d.]+)/ ) || [])[1], 10)
      msie && msie_version <= 9

    add: (e, data) ->
      data.files[0].unique_id = Math.random().toString(36).substr(2,16)
      if add? then add(e, data) else data.submit()

    done: (e, data) ->
      data.result = build_content_object(data.files[0], data.result)
      done(e, data) if done?

    fail: (e, data) ->
      fail(e, data) if fail?

    formData: (form) ->
      unique_id = @files[0].unique_id
      finalFormData[unique_id] =
        key: $this.data('key').replace('{timestamp}', new Date().getTime()).replace('{unique_id}', unique_id).replace('${filename}', sanitizingFilename(@files[0].name))
        'Content-Type': @files[0].type
        acl: $this.data('acl')
        policy: $this.data('policy')
        success_action_status: "201"
        'X-Requested-With': 'xhr'
        'X-Amz-Algorithm': $this.data('amzalgorithm')
        'X-Amz-Credential': $this.data('amzcredential')
        'X-Amz-Date': $this.data('amzdate')
        'X-Amz-Signature': $this.data('amzsignature')

      getFormData(finalFormData[unique_id]).concat(getFormData(extraFormData))

  jQuery.extend settings, options

  to_s3_filename = (filename) ->
    trimmed = filename.replace(/^\s+|\s+$/g,'')
    strip_before_slash = trimmed.split('\\').slice(-1)[0]
    double_encode_quote = strip_before_slash.replace('"', '%22')
    encodeURIComponent(double_encode_quote)

  sanitizingFilename = (filename) ->
    ext = ".#{getExt(filename)}"
    "#{filename.replace(ext, '').replace(/[^\w\s]/gi, '_').replace(/\s/g, "-")}#{ext}"

  getExt = (filename) ->
    idx = filename.lastIndexOf('.')
    if idx < 1 then '' else mapExt(filename.substr(idx + 1))

  mapExt = (extension) ->
    # for now just map audio and video and leave the remaining extensions as they are.
    return 'mp4' if extension in ["3g2", "3gp", "3gp2", "3gpp", "asf", "asr", "asx", "avi", "dif", "dv", "flv", "IVF", "lsf", "lsx", "m1v", "m2t", "m2ts", "m2v", "m4v", "mod", "mov", "movie", "mp2", "mp2v", "mp4", "mp4v", "mpa", "mpe", "mpeg", "mpg", "mpv2", "mqv", "mts", "nsc", "qt", "ts", "tts", "vbk", "wm", "wmp", "wmv", "wmx", "wvx"]
    return 'mp3' if extension in ["aa", "AAC", "aax", "ac3", "ADT", "ADTS", "aif", "aifc", "aiff", "au", "caf", "cdda", "gsm", "m3u", "m3u8", "m4a", "m4b", "m4p", "m4r", "mid", "midi", "mp3", "pls", "ra", "ram", "rmi", "rpm", "sd2", "smd", "smx", "smz", "snd", "wav", "wave", "wax", "wma"]
    extension

  build_content_object = (file, result) ->

    content = {}

    if result # Use the S3 response to set the URL to avoid character encodings bugs
      content.url            = $(result).find("Location").text().replace(/%2F/gi, "/").replace('http:', 'https:')
      content.filepath       = $('<a />').attr('href', content.url)[0].pathname
    else # IE <= 9 returns null result so hack is necessary
      domain = settings.url.replace(/\/+$/, '').replace(/^(https?:)?/, 'https:')
      content.filepath   = finalFormData[file.unique_id]['key'].replace('/${filename}', '')
      content.url        = domain + '/' + content.filepath + '/' + to_s3_filename(file.name)

    content.filename   = sanitizingFilename(file.name)
    content.filesize   = file.size if 'size' of file
    content.filetype   = file.type if 'type' of file
    content.unique_id  = file.unique_id if 'unique_id' of file
    content

  $this.fileupload settings
