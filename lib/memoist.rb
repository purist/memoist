# require 'active_support/core_ext/kernel/singleton_class'
require 'memoist/core_ext/singleton_class'

module Memoist

  def self.memoized_ivar_for(symbol)
    "@_memoized_#{symbol.to_s.sub(/\?\Z/, '_query').sub(/!\Z/, '_bang')}".to_sym
  end

  module InstanceMethods
    def self.included(base)
      base.class_eval do
        unless base.method_defined?(:freeze_without_memoizable)
          alias_method :freeze_without_memoizable, :freeze
          alias_method :freeze, :freeze_with_memoizable
        end
      end
    end

    def freeze_with_memoizable
      memoize_all unless frozen?
      freeze_without_memoizable
    end

    def memoize_all
      prime_cache ".*"
    end

    def unmemoize_all
      flush_cache ".*"
    end

    def prime_cache(*syms)
      syms.each do |sym|
        methods.each do |m|
          if m.to_s =~ /^_unmemoized_(#{sym})/
            if method(m).arity == 0
              __send__($1)
            else
              ivar = Memoist.memoized_ivar_for($1)
              instance_variable_set(ivar, {})
            end
          end
        end
      end
    end

    def flush_cache(*syms)
      syms.each do |sym|
        (methods + private_methods + protected_methods).each do |m|
          if m.to_s =~ /^_unmemoized_(#{sym.to_s.gsub(/\?\Z/, '\?')})/
            ivar = Memoist.memoized_ivar_for($1)
            instance_variable_get(ivar).clear if instance_variable_defined?(ivar)
          end
        end
      end
    end

    def timeout_flush symbol, args, timeout=nil
      return if timeout.nil?

      @memoize_flush_timetable ||= {}
      @memoize_flush_timetable[symbol] ||= {}

      now = Time.now.to_i
      
      if args.nil? or args.length == 0
        args = 0
      end 

      @memoize_flush_timetable[symbol][args] ||= now

      if( now - (@memoize_flush_timetable[symbol][args] ) > timeout )
        @memoize_flush_timetable[symbol].delete args
        flush_cache( symbol )
      end
    end

  end

  def memoize(*m_args)
    if m_args.last and m_args.last.kind_of?( Fixnum )
      timeout = m_args.pop
    end
    symbols = m_args

    symbols.each do |symbol|
      original_method = :"_unmemoized_#{symbol}"
      memoized_ivar = Memoist.memoized_ivar_for(symbol)


      class_eval <<-EOS, __FILE__, __LINE__ + 1
        include InstanceMethods                                                  
                                                                                 
        if method_defined?(:#{original_method})                                  
          raise "Already memoized #{symbol}"                                     
        end                                                                      
        alias #{original_method} #{symbol}                                       
                                                                                 
        if instance_method(:#{symbol}).arity == 0  
          def #{symbol}(reload = false)            
            timeout_flush( :#{symbol}, nil, #{timeout} )

            if reload || !defined?(#{memoized_ivar}) || #{memoized_ivar}.empty?  
              #{memoized_ivar} = [#{original_method}]                            
            end                                                                  
            #{memoized_ivar}[0]                                                  
          end                                                                    
        else                                                                     
          def #{symbol}(*args)                                                   
            #{memoized_ivar} ||= {} unless frozen?                               
            args_length = method(:#{original_method}).arity                      
            if args.length == args_length + 1 &&                                 
              (args.last == true || args.last == :reload)                        
              reload = args.pop                                                  
            end                                                                  
            
            timeout_flush( :#{symbol}, args, #{timeout} )
                                                                
            if defined?(#{memoized_ivar}) && #{memoized_ivar}                    
              if !reload && #{memoized_ivar}.has_key?(args)                      
                #{memoized_ivar}[args]                                           
              elsif #{memoized_ivar}                                             
                #{memoized_ivar}[args] = #{original_method}(*args)               
              end                                                                
            else                                                                 
              #{original_method}(*args)                                          
            end                                                                  
          end                                                                    
        end                                                                      
                                                                                 
        if private_method_defined?(#{original_method.inspect})                   
          private #{symbol.inspect}                                              
        elsif protected_method_defined?(#{original_method.inspect})              
          protected #{symbol.inspect}                                            
        end                                                                      
      EOS
    end
  end
end
