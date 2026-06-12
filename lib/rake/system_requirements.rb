require "shellwords"
require "rubygems/version"

# Uses Gem::Specification#add_system_requirement, provided by RubyGems.

module Rake
  # Derives the named system requirements a built shared object imposes on the
  # install host, by reading the versioned symbols baked into the ELF binary.
  # For each family, the floor is the highest version referenced (the binary
  # needs at least that). These become `name:requirement` tokens in the
  # content-addressable compact index, alongside ruby:/rubygems:.
  #
  # We track glibc and libstdc++ (GLIBCXX), the two that actually predict load
  # failures. CXXABI/GCC are coupled to and implied by libstdc++, so they aren't
  # surfaced separately. This is the runtime-floor slice of what auditwheel
  # inspects for manylinux policies.
  #
  # Auto-derived (never hand-set) so the recorded floors can't drift from what
  # the binary actually requires. Dependency-free so it can be extracted into a
  # standalone audit tool reused by a build farm and CI.
  module SystemRequirements
    # ELF symbol-version family => system requirement name (the compact-index key).
    # The trailing underscore in the scan disambiguates GLIBC_ from GLIBCXX_.
    FAMILIES = {
      "GLIBC"   => "glibc",      # glibc: libc.so.6, libm, libpthread, ...
      "GLIBCXX" => "libstdcxx",  # libstdc++: C++ standard library
    }.freeze

    module_function

    # so_paths: built .so files (a fat binary has one per Ruby version).
    # Returns { name => ">= X.Y.Z", ... } for every family the binaries
    # reference. Empty hash when nothing is determinable.
    def derive(so_paths)
      dumps = Array(so_paths).filter_map { |so| dump(so) if so && File.file?(so) }

      FAMILIES.each_with_object({}) do |(family, name), requirements|
        max = dumps.flat_map { |out| versions(out, family) }.max
        requirements[name] = ">= #{max}" if max
      end
    end

    def versions(dump_output, family)
      dump_output.scan(/#{family}_(\d+(?:\.\d+)+)/).flatten.map { |v| Gem::Version.new(v) }
    rescue StandardError
      []
    end

    # objdump -T is the most portable; readelf -V is the fallback.
    def dump(so_path)
      [["objdump", "-T"], ["readelf", "-V"]].each do |tool, flag|
        next unless system("command -v #{tool} > /dev/null 2>&1")

        out = `#{tool} #{flag} #{Shellwords.escape(so_path)} 2>/dev/null`
        return out unless out.to_s.empty?
      end
      nil
    rescue StandardError
      nil
    end
  end
end
