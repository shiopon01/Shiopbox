require 'aws-sdk'
require 'time'
require 'fileutils'
require 'rb-inotify'

@bucket = 'shiopbox'
@prefix = './' + 'storage' + '/'

Aws.use_bundled_cert!
@client = Aws::S3::Client.new(:region => 'ap-northeast-1')

#---------- SETTING ----------

def upload(key, body)
  @client.put_object(
    :bucket => @bucket,
    :key    => key,
    :body   => File.open(body)
  )
end

def download(key)
  File.open(@prefix + key, "w") do |file|
    @client.get_object(
      :bucket => @bucket,
      :key    => key
    ) do |chunk|
      file.write(chunk)
    end
  end
end

def sync
  #---------- SYNC SETTING ----------

  # get local storage list

  @local_list = Dir.glob(@prefix + "**/*").map do |n|
    next if File.directory?(n)
    n.split(@prefix)[1]
  end.compact!

  # get remote storage's object list

  @remote = @client.list_objects({ bucket: "shiopbox" }).contents.map do |object|
    next if object.key[-1] == '/'
    object
  end.compact!

  # create remote storage list

  @remote_list = @remote.map {|obj| obj.key}

  #---------- SYNC NON DUPLICATE FILES ----------

  # upload now duplicate files

  no_dup_local = @local_list - @remote_list
  no_dup_local.each do |key|
    puts 'upload, local to remote: ' + @prefix + key
    upload(key, @prefix + key)
  end

  # download now duplicate files

  not_dup_remote = @remote_list - @local_list
  not_dup_remote.each do |key|
    puts 'download, remoto to local: ' + @prefix + key
    if key.include?('/')
      FileUtils.mkdir_p(@prefix + key.slice(/.*\//)) unless FileTest.exist?(@prefix + key.slice(/.*\//))
    end
    download(key)
  end
  puts ''

  #---------- SYNC DUPLICATE FILES ----------

  dup = @remote_list & @local_list
  dup.each do |key|

    remote = @remote[@remote_list.find_index key].last_modified
    local  = File.mtime(@prefix + key).utc

    puts 'remote time: ' + remote.to_s
    puts 'local  time: ' + local.to_s

    if local > remote
      # UPLOAD
      puts 'update, local to remote: ' + @prefix + key
      upload(key, @prefix + key)
    else
      # DOWNLOAD
      puts 'update, remote to local: ' + @prefix + key
      download(key)
    end

    puts ''
  end
end

#---------- INOTIFY ----------

notifier = INotify::Notifier.new
notifier.watch("./" + @prefix, :close_write, :moved_to) do |ev|
  $stdout.flush
  $stdout.sync
end

#---------- MAIN ----------

sync()
# notifier.run