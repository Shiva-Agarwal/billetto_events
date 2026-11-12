# Minimal implementation of the TypeID spec (https://github.com/jetify-com/typeid):
#   <prefix>_<26 chars of Crockford base32 encoded UUIDv7>
# e.g. "event_01jcw3d0zqf5ya1b1v3hq0m9xe".
#
# UUIDv7 is time-ordered, so TypeIDs are k-sortable and index-friendly (no random
# B-tree page splits like with UUIDv4), while still being globally unique and
# safe to expose publicly (unlike sequential integer ids).
module TypeId
  ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz".freeze
  PREFIX_FORMAT = /\A[a-z]([a-z_]{0,61}[a-z])?\z/
  SUFFIX_FORMAT = /\A[0-7][#{ALPHABET}]{25}\z/
  InvalidTypeId = Class.new(ArgumentError)

  module_function

  def generate(prefix)
    raise InvalidTypeId, "invalid prefix #{prefix.inspect}" unless PREFIX_FORMAT.match?(prefix.to_s)

    "#{prefix}_#{encode(uuid_v7)}"
  end

  # RFC 9562 UUIDv7 (48-bit unix ms timestamp + random). Ruby >= 3.3 ships SecureRandom.uuid_v7.
  def uuid_v7
    return SecureRandom.uuid_v7 if SecureRandom.respond_to?(:uuid_v7)

    bytes = [ Process.clock_gettime(Process::CLOCK_REALTIME, :millisecond) ].pack("Q>")[2, 6] + SecureRandom.random_bytes(10)
    bytes.setbyte(6, (bytes.getbyte(6) & 0x0f) | 0x70)
    bytes.setbyte(8, (bytes.getbyte(8) & 0x3f) | 0x80)
    bytes.unpack1("H*").unpack("a8a4a4a4a12").join("-")
  end

  def encode(uuid)
    int = Integer(uuid.delete("-"), 16)
    Array.new(26) { |i| ALPHABET[(int >> (5 * (25 - i))) & 0x1f] }.join
  end

  def decode(suffix)
    int = suffix.each_char.reduce(0) { |acc, char| (acc << 5) | ALPHABET.index(char) }
    hex = int.to_s(16).rjust(32, "0")
    [ hex[0, 8], hex[8, 4], hex[12, 4], hex[16, 4], hex[20, 12] ].join("-")
  end

  def parse(tid)
    prefix, _, suffix = tid.to_s.rpartition("_")
    unless PREFIX_FORMAT.match?(prefix) && SUFFIX_FORMAT.match?(suffix)
      raise InvalidTypeId, "invalid type id #{tid.inspect}"
    end

    [ prefix, suffix ]
  end
end
