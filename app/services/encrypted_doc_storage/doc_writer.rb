# frozen_string_literal: true

module EncryptedDocStorage
  class DocWriter
    Result = Struct.new(
      :name,
      :encryption_key,
    )

    def initialize(s3_enabled: false)
      @s3_enabled = s3_enabled
    end

    def write(issuer:, image: nil)
      raise if issuer.blank?

      if image.blank?
        return Result.new(name: nil, encryption_key: nil)
      end

      name = "#{issuer}/#{SecureRandom.uuid}"
      encryption_key = SecureRandom.bytes(32)

      write_with_data(
        image:,
        encryption_key:,
        name:,
      )

      Result.new(
        name:,
        encryption_key: Base64.strict_encode64(encryption_key),
      )
    end

    def write_with_data(image:, encryption_key:, name:)
      storage.write_image(
        encrypted_image: aes_cipher.encrypt(image, encryption_key),
        name:,
      )
    end

    private

    def aes_cipher
      @aes_cipher ||= Encryption::AesCipherV2.new
    end

    def storage
      @storage ||= @s3_enabled ? S3Storage.new : LocalStorage.new
    end
  end
end
