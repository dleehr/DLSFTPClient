Pod::Spec.new do |s|
  s.name         = "DLSFTPClient"
  s.version      = "1.0.0"
  s.summary      = "DLSFPClient is an SFTP Client library  for iOS, using libssh2"
  s.homepage     = "https://github.com/dleehr/DLSFTPClient"
  s.social_media_url = 'https://twitter.com/leehro'
  s.license      = { :type => 'BSD', :file => 'LICENSE' }
  s.author       = { "Dan Leehr" => "dan@hammockdistrict.com" }
  s.source       = {
    :git => "https://github.com/dleehr/DLSFTPClient.git",
    :tag => s.version.to_s
  }

  s.platform     = :ios, '5.1.1'
  s.requires_arc = true

  s.source_files = 'DLSFTPClient/Classes/*.{h,m}'
  s.dependency 'libssh2', '~> 1.4'
  s.framework	 = 'Foundation', 'CFNetwork'
end