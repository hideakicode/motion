# encoding: utf-8

# Copyright (c) 2012, HipByte SPRL and contributors
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

require 'motion/project/builder'

module Motion; module Project
  class Builder
    def archive(config)
      # Create .pkg archive.
      app_bundle = config.app_bundle_raw('MacOSX')
      archive = config.archive
      if !File.exist?(archive) or File.mtime(app_bundle) > File.mtime(archive)
        App.info 'Create', archive
        codesign = begin
          if config.distribution_mode
            "--sign \"" + config.codesign_certificate.sub(/Application/, "Installer") + "\""
          end
        end || ""
        sh "/usr/bin/productbuild --quiet --component \"#{app_bundle}\" /Applications \"#{archive}\" #{codesign}"
      end
    end

    # First signs all frameworks (and the individual versions therein) that it
    # finds in the `Frameworks` directory of the application bundle in the build
    # directory and then signs the application bundle itself.
    #
    # @param [OSXConfig] config
    #        The configuration for this build.
    #
    # @param [String] config
    #        The platform for which to build, which in this case should always
    #        be `MacOSX`.
    #
    # @todo Do we really need the platform parameter when it's always the same?
    #
    def codesign(config, platform)
      frameworks_path = File.join(config.app_bundle(platform), 'Frameworks')
      if File.exist?(frameworks_path)
        Dir.entries(frameworks_path).each do |framework|
          next if framework.start_with?('.')
          versions_path = File.join(frameworks_path, framework, 'Versions')
          Dir.entries(versions_path).each do |version|
            next if version.start_with?('.') || version == 'Current'
            codesign_bundle(config, File.join(versions_path, version))
          end
        end
      end

      codesign_bundle(config, config.app_bundle_raw(platform)) do
        entitlements_path = File.join(config.versionized_build_dir(platform), "Entitlements.plist")
        File.open(entitlements_path, 'w') { |io| io.write(config.entitlements_data) }
        entitlements_path
      end
    end

    private

    # Signs an individual bundle.
    #
    # @param [OSXConfig] config
    #        The configuration for this build.
    #
    # @param [String] bundle
    #        The path to the bundle on disk. In case of a framework, this should
    #        be to the specific version directory inside the `Versions`
    #        directory of the bundle.
    #
    # @yield If a block is given, this will be yielded to allow the generation
    #        of an entitlements file, only when needed.
    #
    # @yieldreturn [String] the path to the entitlements file.
    #
    def codesign_bundle(config, bundle)
      if File.mtime(config.project_file) > File.mtime(bundle) \
          or !system("/usr/bin/codesign --verify '#{bundle}' >& /dev/null")
        App.info 'Codesign', bundle
        entitlements_path = yield if block_given?
        command = "/usr/bin/codesign --force --sign '#{config.codesign_certificate}' "
        command << "--entitlements '#{entitlements_path}' " if entitlements_path
        command << "'#{bundle}'"
        sh(command)
      end
    end
  end
end; end
