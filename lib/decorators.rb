module MethodDecorators
  def self.extended(klass)
    class << klass
      attr_accessor :decorated_methods
    end
  end

  # first, when you write a contract, the decorate method gets called which
  # sets the @decorators variable. Then when the next method after the contract
  # is defined, method_added is called and we look at the @decorators variable
  # to find the decorator for that method. This is how we associate decorators
  # with methods.
  def method_added(name)
    common_method_added name, false
    super
  end

  def singleton_method_added name
    common_method_added name, true
    super
  end

  def common_method_added name, is_class_method
    return unless @decorators

    decorators = @decorators.dup
    @decorators = nil
    @decorated_methods ||= {:class_methods => {}, :instance_methods => {}}

    # attr_accessor on the class variable decorated_methods
    class << self; attr_accessor :decorated_methods; end

    decorators.each do |klass, args|
      # a reference to the method gets passed into the contract here. This is good because
      # we are going to redefine this method with a new name below...so this reference is
      # now the *only* reference to the old method that exists.
      # We assume here that the decorator (klass) responds to .new
      if is_class_method
        decorator = klass.new(self, method(name), *args)
        @decorated_methods[:class_methods][name] = decorator
      else
        decorator = klass.new(self, instance_method(name), *args)
        @decorated_methods[:instance_methods][name] = decorator
      end
    end

    # in place of this method, we are going to define our own method. This method
    # just calls the decorator passing in all args that were to be passed into the method.
    # The decorator in turn has a reference to the actual method, so it can call it
    # on its own, after doing it's decorating of course.
    class_eval <<-ruby_eval, __FILE__, __LINE__ + 1
      def #{is_class_method ? "self." : ""}#{name}(*args, &blk)
        this = self#{is_class_method ? "" : ".class"}
        unless this.respond_to?(:decorated_methods) && !this.decorated_methods.nil?
          raise "Couldn't find decorator for method " + self.class.name + ":#{name}.\nDoes this method look correct to you? If you are using contracts from rspec, rspec wraps classes in it's own class.\nLook at the specs for contracts.ruby as an example of how to write contracts in this case."
        end
        this.decorated_methods[#{is_class_method ? ":class_methods" : ":instance_methods"}][#{name.inspect}].call_with(self, *args, &blk)
      end    
    ruby_eval
  end    

  def decorate(klass, *args)
    @decorators ||= []
    @decorators << [klass, args]
  end
end

class Decorator
  # an attr_accessor for a class variable:
  class << self; attr_accessor :decorators; end

  def self.inherited(klass)
    name = klass.name.gsub(/^./) {|m| m.downcase}

    return if name =~ /^[^A-Za-z_]/ || name =~ /[^0-9A-Za-z_]/

    # the file and line parameters set the text for error messages
    # make a new method that is the name of your decorator.
    # that method accepts random args and a block.
    # inside, `decorate` is called with those params.
    MethodDecorators.module_eval <<-ruby_eval, __FILE__, __LINE__ + 1
      def #{klass}(*args, &blk)
        decorate(#{klass}, *args, &blk)
      end
    ruby_eval
  end

  def initialize(klass, method)
    @method = method
  end
end


