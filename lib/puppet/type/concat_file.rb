require 'puppet/type/file/owner'
require 'puppet/type/file/group'
require 'puppet/type/file/mode'
require 'puppet/util/checksums'

Puppet::Type.newtype(:concat_file) do
  @doc = "Gets all the file fragments and puts these into the target file.
    This will mostly be used with exported resources.

    example:
      Concat_fragment <<| tag == 'unique_tag' |>>

      concat_file { '/tmp/file':
        tag            => 'unique_tag', # Optional. Default to undef
        path           => '/tmp/file',  # Optional. If given it overrides the resource name
        owner          => 'root',       # Optional. Default to undef
        group          => 'root',       # Optional. Default to undef
        mode           => '0644'        # Optional. Default to undef
        order          => 'numeric'     # Optional, Default to 'numeric'
        ensure_newline => false         # Optional, Defaults to false
      }
  "

  ensurable do
    defaultvalues

    defaultto { :present }
  end

  def exists?
    self[:ensure] == :present
  end

  newparam(:tag) do
    desc "Tag reference to collect all concat_fragment's with the same tag"
  end

  newparam(:path, :namevar => true) do
    desc "The output file"

    validate do |value|
      unless (Puppet::Util.absolute_path?(value, :posix) or Puppet::Util.absolute_path?(value, :windows))
        raise ArgumentError, "File paths must be fully qualified, not '#{value}'"
      end
    end
  end

  newparam(:owner, :parent => Puppet::Type::File::Owner) do
    desc "Desired file owner."
  end

  newparam(:group, :parent => Puppet::Type::File::Group) do
    desc "Desired file group."
  end

  newparam(:mode, :parent => Puppet::Type::File::Mode) do
    desc "Desired file mode."
  end

  newparam(:order) do
    desc "Controls the ordering of fragments. Can be set to alpha or numeric."

    newvalues(:alpha, :numeric)

    defaultto :numeric
  end

  newparam(:backup) do
    desc "Controls the filebucketing behavior of the final file and see File type reference for its use."

    validate do |value|
      unless [TrueClass, FalseClass, String].include?(value.class)
        raise ArgumentError, 'Backup must be a Boolean or String'
      end
    end
  end

  newparam(:replace, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    desc "Whether to replace a file that already exists on the local system."
    defaultto :true
  end

  newparam(:validate_cmd) do
    desc "Validates file."

    validate do |value|
      unless value.is_a?(String)
        raise ArgumentError, 'Validate_cmd must be a String'
      end
    end
  end

  newparam(:ensure_newline, :boolean => true, :parent => Puppet::Parameter::Boolean) do
    desc "Whether to ensure there is a newline after each fragment."
    defaultto :false
  end

  # Inherit File parameters
  newparam(:selinux_ignore_defaults, :boolean => true, :parent => Puppet::Parameter::Boolean)

  newparam(:selrange) do
    validate do |value|
      raise ArgumentError, 'Selrange must be a String' unless value.is_a?(String)
    end
  end

  newparam(:selrole) do
    validate do |value|
      raise ArgumentError, 'Selrole must be a String' unless value.is_a?(String)
    end
  end

  newparam(:seltype) do
    validate do |value|
      raise ArgumentError, 'Seltype must be a String' unless value.is_a?(String)
    end
  end

  newparam(:seluser) do
    validate do |value|
      raise ArgumentError, 'Seluser must be a String' unless value.is_a?(String)
    end
  end

  newparam(:show_diff, :boolean => true, :parent => Puppet::Parameter::Boolean)
  # End file parameters

  # Autorequire the file we are generating below
  # Why is this necessary ?
  autorequire(:file) do
    [self[:path]]
  end

  def fragments
    # Collect fragments that target this resource by path, title or tag.
    @fragments ||= catalog.resources.map do |resource|
      next unless resource.is_a?(Puppet::Type.type(:concat_fragment))

      if resource[:target] == self[:path] || resource[:target] == title ||
        (resource[:tag] && resource[:tag] == self[:tag])
        resource
      end
    end.compact
  end

  def should_content
    return @generated_content if @generated_content
    @generated_content = ""
    content_fragments = []

    fragments.each do |r|
      content_fragments << ["#{r[:order]}___#{r[:name]}", fragment_content(r)]
    end

    if self[:order] == :numeric
      sorted = content_fragments.sort do |a, b|
        def decompound(d)
          d.split('___', 2).map { |v| v =~ /^\d+$/ ? v.to_i : v }
        end

        decompound(a[0]) <=> decompound(b[0])
      end
    else
      sorted = content_fragments.sort_by do |a|
        a_order, a_name = a[0].split('__', 2)
        [a_order, a_name]
      end
    end

    @generated_content = sorted.map { |cf| cf[1] }.join

    @generated_content
  end

  def fragment_content(r)
    if r[:content].nil? == false
      fragment_content = r[:content]
    elsif r[:source].nil? == false
      @source = nil
      Array(r[:source]).each do |source|
        if Puppet::FileServing::Metadata.indirection.find(source)
          @source = source 
          break
        end
      end
      self.fail "Could not retrieve source(s) #{r[:source].join(", ")}" unless @source
      tmp = Puppet::FileServing::Content.indirection.find(@source)
      fragment_content = tmp.content unless tmp.nil?
    end

    if self[:ensure_newline]
      fragment_content<<"\n" unless fragment_content =~ /\n$/
    end

    fragment_content
  end

  def generate
    file_opts = {
      :ensure => self[:ensure] == :absent ? :absent : :file,
    }

    [:path,
     :owner,
     :group,
     :mode,
     :replace,
     :backup,
     :selinux_ignore_defaults,
     :selrange,
     :selrole,
     :seltype,
     :seluser,
     :validate_cmd,
     :show_diff].each do |param|
      unless self[param].nil?
        file_opts[param] = self[param]
      end
    end

    metaparams = Puppet::Type.metaparams
    excluded_metaparams = [ :before, :notify, :require, :subscribe, :tag ]

    metaparams.reject! { |param| excluded_metaparams.include? param }

    metaparams.each do |metaparam|
      file_opts[metaparam] = self[metaparam] if self[metaparam]
    end

    [Puppet::Type.type(:file).new(file_opts)]
  end

  def eval_generate
    content = should_content

    if !content.nil? and !content.empty?
      catalog.resource("File[#{self[:path]}]")[:content] = content
    end

    [ catalog.resource("File[#{self[:path]}]") ]
  end
end
