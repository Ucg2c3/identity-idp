# frozen_string_literal: true

# This module is still needed by existing functionality, but any new AES encryption
# should prefer using AesEncryptorV2 and AesCipherV2.
module Encryption
  module Encryptors
    class AesEncryptor
      include Encodable

      DELIMITER = '.'

      # "It is a riddle, wrapped in a mystery, inside an enigma; but perhaps there is a key."
      #  - Winston Churchill, https://en.wiktionary.org/wiki/a_riddle_wrapped_up_in_an_enigma
      #

      def initialize
        self.cipher = AesCipher.new
      end

      def encrypt(plaintext, cek)
        payload = fingerprint_and_concat(plaintext)
        encode(cipher.encrypt(payload, cek))
      end

      def decrypt(ciphertext, cek)
        decrypt_and_test_payload(decode(ciphertext), cek)
      rescue ArgumentError
        raise EncryptionError, 'ciphertext is invalid'
      end

      private

      attr_accessor :cipher

      def fingerprint_and_concat(plaintext)
        fingerprint = Pii::Fingerprinter.fingerprint(plaintext)
        join_segments(plaintext, fingerprint)
      end

      def decrypt_and_test_payload(payload, cek)
        begin
          payload = cipher.decrypt(payload, cek)
        rescue OpenSSL::Cipher::CipherError => err
          raise EncryptionError, err.inspect
        end
        plaintext, fingerprint = split_into_segments(payload)
        return plaintext if Pii::Fingerprinter.verify(plaintext, fingerprint)
      end

      def join_segments(*segments)
        segments.map { |segment| encode(segment) }.join(DELIMITER)
      end

      def split_into_segments(string)
        string.split(DELIMITER).map { |segment| decode(segment) }
      rescue ArgumentError
        raise EncryptionError, 'payload is invalid'
      end
    end
  end
end
