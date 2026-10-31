# qs_check.rb - parse-only syntax checks for Ruby template languages (no rendering).
#   ruby qs_check.rb haml FILE...   Haml 6 (apt ruby-haml): parse + compile the generated Ruby
#   ruby qs_check.rb slim FILE...   Slim (apt ruby-slim): precompile + compile the generated Ruby
# why compile explicitly: Haml 6 turns syntax errors into a runtime raise, so `haml --check`
# reports "Syntax OK" for broken templates.
mode = ARGV.shift
rc = 0
case mode
when "haml"
  require "haml"
  ARGV.each do |f|
    src = File.read(f)
    begin
      Haml::Parser.new({}).call(src)
      RubyVM::InstructionSequence.compile(Haml::Engine.new.call(src), f)
    rescue Haml::Error, SyntaxError => e
      line = e.respond_to?(:line) && e.line ? e.line + 1 : ""
      puts "#{f}:#{line}: #{e.message.lines.first.chomp}"
      rc = 1
    end
  end
when "slim"
  require "slim"
  ARGV.each do |f|
    begin
      RubyVM::InstructionSequence.compile(Slim::Template.new(f).precompiled_template, f)
    rescue Slim::Parser::SyntaxError, SyntaxError => e
      puts "#{f}: #{e.message.lines.first(2).map(&:strip).join(' ')}"
      rc = 1
    end
  end
else
  warn "usage: qs_check.rb haml|slim FILE..."
  exit 2
end
exit rc
