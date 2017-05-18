#
# Description: Creates VM Name with following format:

# Author:      : Dustin Scott, Red Hat
# Creation Date: 19-December-2016
# Updated      : 17-May-2017 by Samson Wick, Red Hat
# NOTE: Number of integers to use for Series is set via the SERIES_COUNT constant
#

# ====================================
# set global method variables
# ====================================

# set method variables
@method = $evm.current_method
@org    = $evm.root['tenant'].name
@debug  = $evm.root['debug'] || false

# set method constants
SERIES_COUNT = 2

# ====================================
# define methods
# ====================================

# define log method
def log(level, msg)
  $evm.log(level,"#{@org} Automation: #{msg}")
end

# get the option from either the tags (lifecycle provision) or from the service dialog (service provision)
def get_options_hash(prov)
  begin
    log(:info, "get_options_hash: Getting options hash via dialog or tags")
    options_hash   = prov.miq_request.options[:dialog]
    options_hash ||= prov.miq_request.options[:ws_values]
    options_hash ||= prov.get_tags
    options_hash ||= prov.miq_request.get_tags

    if options_hash
      log(:info, "get_options_hash: Inspecting options_hash: #{options_hash.inspect}") if @debug
      return options_hash
    else
      raise "Unable to find options_hash"
    end
  rescue => err
    return nil
  end
end

# get operating system attributes from operating system selection
def get_os_attrs(prov, attr)
  begin
    # grab the product name from the template we are current provisioning from
    os_name = prov.source.operating_system.product_name rescue nil

    log(:info, "get_os_attrs: Returning Operating System attribute <#{attr}> for Operating System <#{os_name}>")
    # first we must truncate the product name in a camel case format
    # e.g. Red Hat Enterprise Linux 6 = RedHatEnterpriseLinux6
    truncated_product_name = os_name.split('(').first.delete(' ')

    # return the requested attribute
    $evm.instance_get("/DoS_Variables/Common/OperatingSystems/#{truncated_product_name}")[attr]
  rescue => err
    log(:error, "<#{err}>: Unable to return proper attribute <#{attr}> from os_name <#{os_name}>.  Returning nil.")
    return nil
  end
end

# set derived_name
def set_derived_name(vm_site, vm_os, vm_environment, vm_type, vm_business_unit)
  begin
    # create initial hash
    options_hash = {
        :vm_site          => vm_site,
        :vm_os            => vm_os,
        :vm_environment   => vm_environment,
        :vm_type          => vm_type,
        :vm_business_unit => vm_business_unit
    }
    log(:info, "Inspecting options_hash: #{options_hash.inspect}") if @debug

    # log and check each value
    options_hash.each do |k,v|
      raise "Unable to find critical element #{k} in naming VM" if v.nil?
      log(:info, "Setting derived_name with option: #{k}: #{v}")
    end

    # set vm_name
    derived_name = "#{vm_site}#{vm_os}#{vm_environment}#{vm_type}#{vm_business_unit}".downcase

    # log and return the derived vm name
    log(:info, "Derived VM Name: <#{derived_name}>")
    return derived_name + "$n{#{SERIES_COUNT}}"
  rescue => err
    log(:error, err)
    return nil
  end
end

# log final name and update it on the object
def update_vm_name(name, prov)
  log(:info, "VM Name: <#{name}>")
  $evm.object['vmname'] = name
end

# ====================================
# begin main method
# ====================================

begin
  # log entering method and dump root/object attributes
  $evm.instantiate('/Common/Log/LogBookend' + '?' + { :bookend_status => :enter, :bookend_parent_method => @method, :bookend_org => @org }.to_query)
  [ 'root', 'object' ].each { |object_type| $evm.instantiate("/Common/Log/DumpAttrs?object_type=#{object_type}") if @debug == true }

  # ensure we are using this method in the proper context
  case $evm.root['vmdb_object_type']
    when 'miq_provision_request_template'
      log(:info, "vm_name not required for vmdb_object_type: <#{$evm.root['vmdb_object_type'].inspect}>.  Exiting.")
      exit MIQ_OK
    when 'miq_provision', 'miq_provision_request'
      prov = $evm.root['miq_provision'] || $evm.root['miq_provision_request']
    else
      raise "Invalid $evm.root['vmdb_object_type']: #{$evm.root['vmdb_object_type']}"
  end

  # get relevant options from provisioning object and debug logging
  if prov
    log(:info, "Inspecting provisioning object: #{prov.inspect}") if @debug
    current_vm_name = prov.get_option(:vm_name).to_s.strip
    vms_requested   = prov.get_option(:number_of_vms)
    options_hash    = get_options_hash(prov)

    # log current name from dialog
    log(:info, "vm_name from dialog:<#{current_vm_name.inspect}>")

    if options_hash
      # no vm name chosen from dialog, or changeme requested
      if current_vm_name.blank? || current_vm_name == 'changeme'
        derived_name = set_derived_name(
            options_hash[:xom_site],
            options_hash[:xom_os],
            options_hash[:xom_environment],
            options_hash[:xom_type],
            options_hash[:xom_business_unit]
            #{get_os_attrs(prov, 'vm_name_os_family'),
            #get_os_attrs(prov, 'vm_name_os_version'),
            #options_hash[:dos_function]}"
        )
      else
        if vms_requested == 1
          derived_name = current_vm_name
        else
          derived_name = "#{current_vm_name}$n{#{SERIES_COUNT}}"
        end
      end

      # set the vm name if we derived one successfully
      if derived_name
        update_vm_name(derived_name, prov)
      else
        raise "Unable to determine derived_name"
      end
    else
      raise "Unable to find options_hash"
    end
  else
    raise "Could not find provisioning object"
  end

  # ====================================
  # log end of method
  # ====================================

  # log exiting method and exit with MIQ_OK status
  $evm.instantiate('/Common/Log/LogBookend' + '?' + { :bookend_status => :exit, :bookend_parent_method => @method, :bookend_org => @org }.to_query)
  exit MIQ_OK

# set ruby rescue behavior
rescue => err
  # go back to default naming if we have an error
  log(:warn, "Reverting to default vm_name")
  log(:warn, "[#{err}]\n#{err.backtrace.join("\n")}")

  # inspect objects for debugging purposes
  log(:info, "Inspecting prov object: #{prov.inspect}")

  # log and update the vm name
  update_vm_name(current_vm_name, prov)

  # get errors variables (or create new hash) and set message
  message = "Unable to successfully complete method: <b>#{@method}</b>.  VM Name may not be set correctly."
  errors  = prov.get_option(:errors) || {}

  # set hash with this method error
  errors[:vm_name_error] = message
  prov.set_option(:errors, errors)

  # log exiting method
  $evm.instantiate('/Common/Log/LogBookend' + '?' + { :bookend_status => :exit, :bookend_parent_method => @method, :bookend_org => @org }.to_query)
  exit MIQ_WARN
end
