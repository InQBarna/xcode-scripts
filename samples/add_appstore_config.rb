#!/usr/bin/ruby
#Add  -w at the end of ruby for warnings

require 'xcodeproj'


# Method to add config to project
def create_new_appstore_project_config(project, copied_config, config_class = Xcodeproj::Project::Object::XCBuildConfiguration)
  config_name = "AppStore"
  project.new(config_class).tap do |newconfig|
    puts "  Adding Configuration '#{config_name}' to project "+project.path.cleanpath.to_path
    newconfig.name = config_name
    if copied_config != nil
        newconfig.build_settings = copied_config.build_settings
        newconfig.base_configuration_reference = copied_config.base_configuration_reference
    end
    project.build_configurations << newconfig
  end
end

# Method to add config to target
def create_new_appstore_target_config(target, copied_config, config_class = Xcodeproj::Project::Object::XCBuildConfiguration)
  config_name = "AppStore"
  target.project.new(config_class).tap do |newconfig|
    puts "  Adding Configuration '#{config_name}' to target "+target.name
    newconfig.name = config_name
    if copied_config != nil
        newconfig.build_settings = copied_config.build_settings
        newconfig.base_configuration_reference = copied_config.base_configuration_reference
    end
    target.build_configurations << newconfig
  end
end

# Open project and add build phase
project_path = "./LaVanguardia.xcodeproj";
puts "Checking for existing configurations in project " + project_path;
project = Xcodeproj::Project.open(project_path);
copied_config = nil
project.build_configurations.each do |cur_config|
    puts " Found configuration "+cur_config.name
    if cur_config.name == "Distribution"
        puts " Please rename Distribution config to 'AppStore'"
        puts " Nothing to do. Exiting"
        exit
    end
    if cur_config.name == "AppStore"
        puts " Nothing to do. Exiting"
        exit
    end
    if cur_config.name == "Release"
        copied_config = cur_config
    end
end
create_new_appstore_project_config(project, copied_config)

project.targets.each do |native_target|
    native_target.build_configurations.each do |cur_config|
        puts " Found configuration "+cur_config.name+" for target "+native_target.name
        if cur_config.name == "Distribution"
            puts " Please rename Distribution config to 'AppStore'"
            puts " Nothing to do. Exiting"
            exit
        end
        if cur_config.name == "AppStore"
            puts " Nothing to do. Exiting"
            exit
        end
        if cur_config.name == "Release"
            copied_config = cur_config
        end
    end
    create_new_appstore_target_config(native_target, copied_config)
end
project.save();
puts ""

# Put project back to json format
puts "Touching project file to convert to json format"
puts ""
exec( "xcproj touch "+project_path )