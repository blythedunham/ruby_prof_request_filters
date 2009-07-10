# = RubyProfRequestFilters
# Output ruby prof results to your browser for the specified request when the url includes parameter <tt>ruby_prof=true</tt>
#   http://localhost:3000/?ruby_prof=true
#
# == Install
#   script/plugin install http://github.com/blythedunham/ruby_prof_request_filters
#
# == Usage
# Include +RubyProfRequestFilters+ in the controller. Return false from +ruby_prof_filters_enabled?+
# to dynamically use ruby prof
#   class ApplicationController < ActionView::Base
#     include RubyProfRequestFilters
#     
#     def ruby_prof_filters_enabled?; !Rails.env.production?; end
#   end
#
# == Options
# The following parameters can be specified on the url
#
# === +ruby_prof_graph+
# * +flat+ a flat text graph
# * +graph+ text graphed results
# * +graph_html+ (default) graphed results in html
#
# ===+ruby_prof_measure+ 
# Specify which type of measurement to use. Some options involve additional configuration
# * process_time (default)
# * wall_time
# * cpu_time
# * allocations
# * memory
# * gc_runs
# * gc_time
#
# Example:
#   http://localhost:3000/?ruby_prof=true&ruby_prof_measure=memory
# These are explained in depth on the rubyprof website: http://ruby-prof.rubyforge.org
#
# === Developers
# * Blythe Dunham http://snowgiraffe.com
#
# === Homepage
# * Github Project: http://github.com/blythedunham/ruby_prof_request_filters/tree/master
# * Install:  <tt>script/plugin install git://github.com/blythedunham/ruby_prof_request_filters</tt>
module RubyProfRequestFilters
  def self.included( base )
    base.send :around_filter, :profile_with_ruby_prof, :if => :can_profile_with_ruby_prof?
  end

  # Return true if the profiler is enabled. Overwrite this on the controller for specifics
  # For example, disable when in production mode
  #  !Rails.env.production?
  def ruby_prof_filters_enabled?; true; end

  # Return true when the ruby_prof parameter is specified
  # and ruby_prof_filters are enabled
  def can_profile_with_ruby_prof?
    params[ :ruby_prof ] && ruby_prof_filters_enabled?
  end

  # The around filter method to use ruby prof for this request
  # If you wish to enable it for only a few controllers, set ruby_filters_enabled? to false in 
  # applications_controller.rb
  def profile_with_ruby_prof
    logger.info "PROFILING with RubyProf...."

    return false unless load_ruby_prof

    output = exception = result = nil

    result = RubyProf.profile do

      begin
        output = yield
      rescue => e
        exception = e
        logger.error( ruby_prof_print_exception( exception ) )
      end

    end

    render_ruby_prof_results( result, output, exception )
    true

  rescue => ruby_prof_exception
    logger.error ruby_prof_print_exception( ruby_prof_exception )

    #stop the chain if there are errors
    return false
  end

  protected

  # Render the ruby_prof results. Print the exception message on top of the
  # profiling data if an exception was thrown up to +ruby_prof_request_filters+
  def render_ruby_prof_results( result, output=nil, exception=nil )

    # clear the page so we can render a second time
    unless (nothing_rendered = !performed?)
      @performed_render = @performed_redirect = nil
    end

    ruby_prof_page = draw_ruby_prof_results( result )

    if nothing_rendered || exception
      render :text => ruby_prof_error_message_page( ruby_prof_page, exception ), :status => 500
    else
      render :text => ruby_prof_page
    end

  end

  # Render the results
  # The options can be specified as parameter +ruby_prof_graph+ in the request
  #  http://localhost:3000/?ruby_prof=true&ruby_prof_graph=flat
  #
  # The options are:
  #  * +flat+ a flat text graph
  #  * +graph+ text graphed results
  #  * +graph_html+ (default) graphed results in html
  def draw_ruby_prof_results( result )

    graph_klass = case params[ :ruby_prof_graph ].to_s
      when 'flat'  then RubyProf::FlatPrinter
      when 'graph' then RubyProf::GraphPrinter
      else
        RubyProf::GraphHtmlPrinter
    end
 
    response.content_type = (graph_klass == RubyProf::GraphHtmlPrinter ? Mime::HTML : Mime::TEXT)

    out = StringIO.new
    graph_klass.new(result).print(out)
    out.string
  end

  #Print the error message
  def ruby_prof_print_exception( exception )#:nodoc:
    error_message =  "AN ERROR HAS OCCURRED WHILE PROFILING:\n"
    error_message << "#{ exception.class }: #{ exception }\n" if exception
    error_message << exception.backtrace.join( "\n" ) if exception && exception.backtrace
    error_message.gsub!("\n", '<br>') if response.content_type == Mime::HTML
    error_message
  end

  #Write the exception if one occurred
  def ruby_prof_error_message_page( ruby_prof_page, exception )#:nodoc:
    error_page = ruby_prof_print_exception( exception )
    error_page << "\n\n\n"
    error_page << ruby_prof_page
    error_page
  end

  # Load ruby prof. Requires it here
  # Will complain and stop the request chain if ruby_prof is not installed
  # The +ruby_prof_measure+ param specifies which type of measurement to use
  # * process_time (default)
  # * wall_time
  # * cpu_time
  # * allocations
  # * memory
  # * gc_runs
  # * gc_time
  # These are explained in depth on the rubyprof website: http://ruby-prof.rubyforge.org/
  #   http://localhost:3000/?ruby_prof=true&ruby_prof_measure=wall_time
  def load_ruby_prof
    begin
      #gem 'ruby-prof', '>= 0.6.1'
      require 'ruby-prof'
      if mode = params[ :ruby_prof_measure ]
        RubyProf.measure_mode = RubyProf.const_get( mode.upcase )
      end
      true
    rescue LoadError
      render :text => 'gem install ruby-prof to use the ruby_profr' unless performed?
      return false
    end
  end
end