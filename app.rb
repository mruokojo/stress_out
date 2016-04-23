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


client = TinyTds::Client.new username: ENV['db_user'], password: ENV['db_pw'],
                             host: ENV['db_address'],
                             port: 1433, database: 'dbStressOut', azure: true

ap "is client active: #{client.active?}"
exit

av_session = AVCapture::Session.new
dev = AVCapture.devices.find(&:video?)

p dev.name
p dev.video?


av_session.run_with(dev) do |connection|
  2.times do |i|
    img_path='shots'
    img_name="stress_out_#{Time.now.to_i}.jpg"
    img_filename="#{img_path}/#{img_name}"
    File.open(img_filename, 'wb') { |f|
      f.write connection.capture
    }
    if i > 0
      puts "Sending picture #{img_name}..."

      Net::SFTP.start(ENV['ftp_address'], ENV['ftp_user'], :password => ENV['ftp_pw']) do |sftp|
        # upload a file or directory to the remote host
        sftp.upload!(img_filename, "public_html/stressout/#{img_name}")
      end
      url="http://www.nomenal.fi/stressout/#{img_name}"
      puts "Analyzing picture #{url}..."
      results=HTTParty.post('https://api.projectoxford.ai/face/v1.0/detect?returnFaceAttributes=age,gender,glasses,headPose,smile,facialHair',
                            body: {'url' => url}.to_json,
                            headers: {'Ocp-Apim-Subscription-Key' => ENV['msft_face_key'],
                                      'Content-Type' => 'application/json'})


      ap results
      # Emotions

      results=HTTParty.post('https://api.projectoxford.ai/emotion/v1.0/recognize',
                            body: {'url' => url}.to_json,
                            headers: {'Ocp-Apim-Subscription-Key' => ENV['msft_emotion_key'],
                                      'Content-Type' => 'application/json'})

      ap results

      # results=HTTParty.post("https://api.kairos.com/media?timeout=0&source=http://www.nomenal.fi/stressout/#{img_filename}",
      #                       headers: {
      #                           'app_id' => ENV['kairos_app'],
      #                           'app_key' => ENV['kairos_key']})
      # media_id = results['id']
      # File.open('media-ids.txt', 'a') { |f|
      #   f.puts media_id
      # }
      #
      # while results['status_code'] == '2' && media_id
      #   sleep 5
      #   results=HTTParty.get("https://api.kairos.com/media/#{media_id}",
      #                        headers: {
      #                            'app_id' => ENV['kairos_app'],
      #                            'app_key' => ENV['kairos_key']})
      #   ap results
      # end
    end
    #sleep 1
  end
end
