#!/usr/bin/ruby
=begin
  parser/ruby.rb - parser for ruby script

  Copyright (C) 2003-2005  Masao Mutoh
  Copyright (C) 2005       speakillof
  Copyright (C) 2001,2002  Yasushi Shoji, Masao Mutoh
 
  You may redistribute it and/or modify it under the same
  license terms as Ruby.

  $Id: ruby.rb,v 1.13 2008/12/01 14:30:30 mutoh Exp $
=end

require 'irb/ruby-lex.rb'
require 'stringio'
require 'gettext/translation_target.rb'

class RubyLexX < RubyLex  # :nodoc: all
  # Parser#parse resemlbes RubyLex#lex
  def parse
    until (  (tk = token).kind_of?(RubyToken::TkEND_OF_SCRIPT) && !@continue or tk.nil?  )
      s = get_readed
      if RubyToken::TkSTRING === tk
        def tk.value
          @value 
        end
        
        def tk.value=(s)
          @value = s
        end
        
        if @here_header
          s = s.sub(/\A.*?\n/, '').sub(/^.*\n\Z/, '')
        else
          begin
            s = eval(s)
          rescue Exception
            # Do nothing.
          end
        end
        
        tk.value = s
      end
      
      if $DEBUG
        if tk.is_a? TkSTRING
          $stderr.puts("#{tk}: #{tk.value}")
        elsif tk.is_a? TkIDENTIFIER
          $stderr.puts("#{tk}: #{tk.name}")
        else
          $stderr.puts(tk)
        end
      end
      
      yield tk
    end
    return nil
  end

  # Original parser does not keep the content of the comments,
  # so monkey patching this with new token type and extended
  # identify_comment implementation
  RubyToken.def_token :TkCOMMENT_WITH_CONTENT, TkVal

  def identify_comment
    @ltype = "#"
    get_readed # skip the hash sign itself

    while ch = getc
      if ch == "\n"
        @ltype = nil
        ungetc
        break
      end
    end
    return Token(TkCOMMENT_WITH_CONTENT, get_readed)
  end

end

module GetText
  module RubyParser
    extend self
    
    ID = ['gettext', '_', 'N_', 'sgettext', 's_']
    PLURAL_ID = ['ngettext', 'n_', 'Nn_', 'ns_', 'nsgettext']
    MSGCTXT_ID = ['pgettext', 'p_']
    MSGCTXT_PLURAL_ID = ['npgettext', 'np_']

    def parse(file, targets = [])  # :nodoc:
      lines = IO.readlines(file)
      parse_lines(file, lines, targets)
    end

    def parse_lines(file_name, lines, targets)  # :nodoc:
      file = StringIO.new(lines.join + "\n")
      rl = RubyLexX.new
      rl.set_input(file)
      rl.skip_space = true
      #rl.readed_auto_clean_up = true

      target = nil
      line_no = nil
      last_extracted_comment = ''
      reset_extracted_comment = false
      rl.parse do |tk|
        begin
          case tk
          when RubyToken::TkIDENTIFIER, RubyToken::TkCONSTANT
            if ID.include?(tk.name)
              target = TranslationTarget.new(:normal)
            elsif PLURAL_ID.include?(tk.name)
              target = TranslationTarget.new(:plural)
            elsif MSGCTXT_ID.include?(tk.name)
              target = TranslationTarget.new(:msgctxt)
            elsif MSGCTXT_PLURAL_ID.include?(tk.name)
              target = TranslationTarget.new(:msgctxt_plural)
            else
              target = nil
            end
            line_no = tk.line_no.to_s
          when RubyToken::TkSTRING
            target.set_current_attribute tk.value if target
          when RubyToken::TkPLUS, RubyToken::TkNL
            #do nothing
          when RubyToken::TkCOMMA
            target.advance_to_next_attribute if target
          else
            if target && target.msgid
              existing = targets.find_index {|t| t.matches?(target)}
              if existing
                target = targets[existing].merge(target)
                targets[existing] = target
              else
                targets << target
              end
              target.occurrences << file_name + ":" + line_no
              target.add_extracted_comment last_extracted_comment unless last_extracted_comment.empty?
              target = nil
            end
          end
        rescue
          $stderr.print "\n\nError"
          $stderr.print " parsing #{file_name}:#{tk.line_no}\n\t #{lines[tk.line_no - 1]}" if tk
          $stderr.print "\n #{$!.inspect} in\n"
          $stderr.print $!.backtrace.join("\n")
          $stderr.print "\n"
          exit 1
        end

        case tk 
        when RubyToken::TkCOMMENT_WITH_CONTENT
          last_extracted_comment = "" if reset_extracted_comment
          if last_extracted_comment.empty?
            # new comment from programmer to translator?
            comment1 = tk.value.lstrip
            if comment1 =~ /^TRANSLATORS\:/
              last_extracted_comment += $'
            end
          else
            last_extracted_comment += "\n" 
            last_extracted_comment += tk.value
          end
          reset_extracted_comment = false
        when RubyToken::TkNL
        else
          reset_extracted_comment = true
        end
      end
      targets
    end

    def target?(file)  # :nodoc:
      true # always true, as default parser.
    end
  end 
end



if __FILE__ == $0
  require 'pp'
  ARGV.each do |file|
    pp GetText::RubyParser.parse(file)
  end
  
  #rl = RubyLexX.new; rl.set_input(ARGF)  
  #rl.parse do |tk|
    #p tk
  #end  
end
