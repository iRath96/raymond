#! ruby

$INPUT_FILES = (0...ENV["SCRIPT_INPUT_FILE_COUNT"].to_i).map { |i| ENV["SCRIPT_INPUT_FILE_#{i}"] }
$OUTPUT_PATH = File.join(ENV["BUILT_PRODUCTS_DIR"], ENV["UNLOCALIZED_RESOURCES_FOLDER_PATH"])

$REWRITE_DIRECTORIES = $INPUT_FILES.map { |path| File.basename path }

def is_source_file(filename)
    extension = filename.split(".").last.downcase
    return ["metal", "cpp", "c", "hpp", "h"].include? extension
end

def process_file(input_path, output_path, depth)
    return unless is_source_file(File.basename(input_path))

    input = File.read(input_path, :encoding => "iso-8859-1")
    output = input.gsub(/^#include <(.*)>$/) do |match|
        path = $1
        base = path.split("/").first
        next "#include <#{path}>" unless $REWRITE_DIRECTORIES.include? base

        new_path = "../" * depth + path
        #puts "rewriting #{path} -> #{new_path}"
        next "#include \"#{new_path}\""
    end
    File.write(output_path, output)
end

def process_entry(path, output_path, depth=0)
    return process_file(path, output_path, depth) if File.file? path
    
    Dir.mkdir output_path unless File.exist? output_path
    Dir.children(path).each do |entry|
        subpath = File.join path, entry
        subout = File.join output_path, entry
        process_entry subpath, subout, (depth + 1)
    end
end

$INPUT_FILES.each do |directory|
    process_entry(directory, File.join($OUTPUT_PATH, File.basename(directory)))
end
