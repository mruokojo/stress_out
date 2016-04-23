# -*- encoding : utf-8 -*-
require 'av_capture'
require 'httparty'
require 'net/sftp'
require 'ap'
require 'dotenv'
require 'rollbar'
require 'sequel'
require 'tiny_tds'
Dotenv.load

puts "Connecting to database at #{ENV['db_address']}..."
DB = Sequel.connect(adapter: 'tinytds', host: ENV['db_address'], database: 'dbStressOut', user: ENV['db_user'], password: ENV['db_pw'], azure: true)
# DB['SELECT * FROM dbo.tblEmotions'].all do |row|
#   ap row
# end

faces=DB[:tblFaces]
emotions= DB[:tblEmotions]

av_session = AVCapture::Session.new
dev = AVCapture.devices.find(&:video?)
p "Camera name is #{dev.name}"

av_session.run_with(dev) do |connection|
  20.times do |i|
    img_path='shots'
    img_name="stress_out_#{Time.now.to_i}.jpg"
    img_filename="#{img_path}/#{img_name}"
    File.open(img_filename, 'wb') { |f|
      f.write connection.capture
    }
    puts "Sending picture #{img_name}..."
    remote_filename="public_html/stressout/#{img_name}"
    Net::SFTP.start(ENV['ftp_address'], ENV['ftp_user'], :password => ENV['ftp_pw']) do |sftp|
      # upload a file or directory to the remote host
      sftp.upload!(img_filename, remote_filename)
    end
    url="http://www.nomenal.fi/stressout/#{img_name}"
    puts 'Analyzing faces in picture...'
    face_results=HTTParty.post('https://api.projectoxford.ai/face/v1.0/detect?returnFaceAttributes=age,gender,glasses,headPose,smile,facialHair',
                               body: {'url' => url}.to_json,
                               headers: {'Ocp-Apim-Subscription-Key' => ENV['msft_face_key'],
                                         'Content-Type' => 'application/json'})


    face_results.each do |fr|
      ap fr
      faces.insert(
          :face_id => fr['faceId'],
          :top => fr['faceRectangle']['top'],
          :left => fr['faceRectangle']['left'],
          :width => fr['faceRectangle']['width'],
          :height => fr['faceRectangle']['height'],
          :smile => fr['faceAttributes']['smile'],
          :pitch => fr['faceAttributes']['headPose']['pitch'],
          :roll => fr['faceAttributes']['headPose']['roll'],
          :yaw => fr['faceAttributes']['headPose']['yaw'],
          :gender => fr['faceAttributes']['gender'],
          :age => fr['faceAttributes']['age'],
          :moustache => fr['faceAttributes']['facialHair']['moustache'],
          :beard => fr['faceAttributes']['facialHair']['beard'],
          :side_burns => fr['faceAttributes']['facialHair']['sideburns'],
          :glasses => fr['faceAttributes']['glasses'],
          :created_at => Time.now,
          :updated_at => Time.now
      )
    end

    puts 'Analyzing emotions in picture...'
    # Emotions
    emotion_results=HTTParty.post('https://api.projectoxford.ai/emotion/v1.0/recognize',
                                  body: {'url' => url}.to_json,
                                  headers: {'Ocp-Apim-Subscription-Key' => ENV['msft_emotion_key'],
                                            'Content-Type' => 'application/json'})

    emotion_results.each do |er|
      face_id=nil
      face_results.each do |fr|
        if (fr['faceRectangle']['top'] == er['faceRectangle']['top']) ||
            (fr['faceRectangle']['left'] == er['faceRectangle']['left']) ||
            (fr['faceRectangle']['width'] == er['faceRectangle']['width']) ||
            (fr['faceRectangle']['height'] == er['faceRectangle']['height'])
          face_id=fr['faceId']
        end
      end
      emotions.insert(
          :height => er['faceRectangle']['height'],
          :left => er['faceRectangle']['left'],
          :top => er['faceRectangle']['top'],
          :width => er['faceRectangle']['width'],
          :face_id => face_id,
          :anger => er['scores']['anger'],
          :contempt => er['scores']['contempt'],
          :disgust => er['scores']['disgust'],
          :fear => er['scores']['fear'],
          :happiness => er['scores']['happiness'],
          :neutral => er['scores']['neutral'],
          :sadness => er['scores']['sadness'],
          :surprise => er['scores']['surprise'],
          :created_at => Time.now,
          :updated_at => Time.now
      )
      puts 'New emotion inserted'
      ap er
    end
    puts 'Removing processed image...'
    Net::SFTP.start(ENV['ftp_address'], ENV['ftp_user'], :password => ENV['ftp_pw']) do |sftp|
      sftp.remove!(remote_filename)
    end
    File.delete(img_filename)
  end
end
