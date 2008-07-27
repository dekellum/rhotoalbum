#!/usr/bin/env ruby
# Rhotoalbum -- a Ruby photo album generator.
#
# Copyright (C) 2007-2008  Ondrej Jaura
# Contributor(s): Viktor Zigo
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# Ondrej Jaura <ondrej@valibuk.net>
# Viktor Zigo <viz@alephzarro.com>


# Rhotoalbum -- a Ruby photo album generator.
#
# Ondrej Jaura <ondrej@valibuk.net>
# Viktor Zigo <viz@alephzarro.com>
#
# version: 0.6
#
require 'yaml'
require 'fileutils'
require 'uri'

require 'optional_require'
EXIF_LIB = optional_require('exifr')

module RhotoAlbum

    OPTIONS_FILE = 'options.yml'
    CMDS = ['generate', 'text', 'clean', 'cleanindex']    
    DEFAULTS =  {
        :title=>'Rhotoalbum',
        :author=>'Ondrej Jaura, Viktor Zigo',
        :author_label => 'Authors',
        :css=>'rhotoalbum.css',
        :explicitIndexHtml => false,
        :styleSwitcher => true,
        :showTitleAlbum => true,
        :showStatsAlbum => true,
        :showTitlePhoto => true,
        :showDescription => true,
        :showDate => true,
        :showExif => true,
        :showExtendedExif => true,
        :thumbnailDim => '256x256',
        :panning => false,
        :fading => false,
        :labelNoPhoto => 'no photos',
        :labelOnePhoto => 'one photo',
        :labelMorePhotos => '# photos',
        :labelOneAlbum => 'one album',
        :labelMoreAlbums => '# albums'
    }
#    DEFAULTS[:copyright]=%Q{
#        <a rel="license" href="http://creativecommons.org/licenses/by-nc-nd/3.0/"><img alt="Creative Commons License" style="border-width:0" src="http://i.creativecommons.org/l/by-nc-nd/3.0/80x15.png" /></a> This work is licensed under a <a rel="license" href="http://creativecommons.org/licenses/by-nc-nd/3.0/" title="Creative Commons Attribution-Noncommercial-No Derivative Works 3.0 License">CC NC ND</a>.    
#    }


    HIGHLIGHT = 'highlight.jpg'
    THUMBNAILS_DIR = 'thumbnails'
    VERSION = '0.6'

  # A base class for any page generator.
  #
  class MetaPageGenerator

    # Initialises the page generator.
    #
    def initialize out, path, scriptGenerator, thumbnailGenerator, opts = {}
      @opts = opts
      @out = out
      @path = path
      @scriptGenerator = scriptGenerator
      @thumbnailGenerator = thumbnailGenerator
    end

    def generate subdirs, images, texts
      generate_header
      @scriptGenerator.generate @out, images, @path
      generate_body subdirs, images, texts
      generate_footer
    end    
  end

  # A JavaScript part of the page generator.
  #
  class ScriptGenerator
    def initialize opts = {}
      @opts = opts
    end

    def generate_beginning out, path
      relative = Helper.relativise path.size - 1
      #optional Style Switcher
      out << %Q{ 
        <script type="text/javascript" src="#{relative}switcher.js"></script>
      } if @opts[:styleSwitcher]
      
      # image viewer - Slider
      out << %Q{
        <script type="text/javascript" src="#{relative}slide.js"></script>
        <script type=\"text/javascript\">
        <!--
            var viewer = new PhotoViewer();\n
	    viewer.disableEmailLink();\n
	    viewer.disableEmailLink();\n

        }
        out << "      viewer.disablePanning();\n" if not @opts[:panning]
        out << "      viewer.enableAutoPlay();\n" if false
        out << "      viewer.disableFading();\n" if not @opts[:fading]
    end

    def generate_end out
      out <<
"   //--></script>\n"
    end

    def generate_file_entry out, image
      out << "      viewer.add('#{image}', '#{ImageInfo.image_name image}', '#{ImageInfo.image_timestamp image}');\n"
    end

    def generate out, images, path
      generate_beginning out, path
      images.each do |i|
        next if i == HIGHLIGHT
        generate_file_entry out, i
      end
      generate_end out
    end
  end

  # A page generator.
  #
  class PageGenerator < MetaPageGenerator

    # Returns a navigational URL. Currently, only 'home', 'up' and 'down' are supported.
    def navigate relation, args = {}
      url = case relation
              when 'home' then Helper.relativise @path.size - 1;
              when 'up'   then Helper.relativise args[:level]
              when 'down' then args[:subdir] + '/';
            end
      url += 'index.html' if @opts[:explicitIndexHtml]
      return url
    end

    def generate_menu images, subdirs
      @out << '<div class="menu">'
      i = @path.size - 1
      @path.each do |p|
        if p == @path.last
          @out << '<span class="actual-item">'
        else
          @out << '<a class="normal-item"'
          @out << " href=\"#{navigate 'up', :level => i}\">"
        end

        if p == @path.first
          @out << "#{@opts[:title]}"
        else
          @out << "#{p}"
        end

        if p == @path.last
          @out << '</span>'
        else
          @out << '</a>'
          @out << ' :: '
        end

        i -= 1
      end

      # statistics
      if @opts[:showStatsAlbum]
        stats = []

        stats_images = number_of_images(images, false)
        stats.push stats_images unless stats_images.empty?

        stats_subalbums = number_of_subalbums(subdirs)
        stats.push stats_subalbums unless stats_subalbums.empty?

        @out << "<span class=\"menu-details\">#{stats.join(' &nbsp; / &nbsp; ')}</span>"
      end

      #Theme switching 
      @out <<  %Q{
        <div class="skin">
            Skin:
            <a href="#" onclick="setActiveStyleSheet('black'); return false;">Black</a>,
            <a href="#" onclick="setActiveStyleSheet('white'); return false;">White</a>
        </div>
      } if @opts[:styleSwitcher]
      @out << '</div>'
    end

    def generate_subdirs subdirs, texts
      subdirs.each do |s|
        desc= texts[s]
        @out << %Q{
            <div class="index-item album">
            <a href="#{navigate 'down', :subdir => s}">
                <img class="image" src="#{s}/#{HIGHLIGHT}" alt="Album: #{s}"/>
                #{"<span class=\"title\">#{s}</span>" if @opts[:showTitleAlbum]}
            </a>
            #{ "<span class=\"description\">#{desc}</span>" if desc and @opts[:showDescription]}
            #{ "<span class=\"statistics\">#{number_of_images(Dir[s + '/**/' + Generator::IMAGE_MASK].reject do |f| f.include? THUMBNAILS_DIR or f.include? HIGHLIGHT end)}</span>" if @opts[:showStatsAlbum]}
            </div>
        }
      end
    end

    def generate_images images, texts
      k = 0 # index
      firstThumbnail = nil # the first image thumbnail
      hasHighlight = false # does the directory contain a highlight image?

      images.each do |i|                
        if i == HIGHLIGHT
          hasHighlight = true
          next
        end

        #if k % 2 == 0 # Uncomment this line if you have a double-thumbnail problem. (Fix by Michael Adams)

          showExif = false
          j = nil
          if @opts[:showExif] && EXIF_LIB # if enabled and the exif library is loaded
            j = EXIFR::JPEG.new(i)
            showExif = j.exif? # show exif only if the image contains exif info
          end

          desc= texts[i]
          thumbnail = @thumbnailGenerator.thumbnail(i) # create a thumbnail
          firstThumbnail = thumbnail if firstThumbnail == nil # remember the first thumbnail

          @out << %Q{
              <div class="image-item photo #{'first-image-item' if k == 0}">
              <a href="#{URI.escape(i)}" onclick="return viewer.show(#{k})"><img class="image" src="#{URI.escape(thumbnail)}" alt="#{i}" title="#{i}"/></a>
              #{"<span class=\"datum\">#{ImageInfo.image_timestamp i}</span>" if @opts[:showDate]}
              #{"<span class=\"title\">#{ImageInfo.image_name i}</span>" if @opts[:showTitlePhoto]}
              #{"<span class=\"description\">#{desc}</span>" if desc and @opts[:showDescription]}
              #{"<span class=\"exifBasic\">#{j.exif[:exposure_time].to_s} sec, #{j.exif[:focal_length]} mm, F#{j.exif[:f_number].to_f}</span>" if showExif}
              #{"<span class=\"exifExtended\">#{j.exif[:model]}</span>" if showExif && @opts[:showExtendedExif]}
              </div>
          }
        #end # Uncomment this line if you have a double-thumbnail problem.  (Fix by Michael Adams)
        k += 1
      end

      # if there is no highlight image, set it to the first image
      if ! hasHighlight and firstThumbnail != nil
        puts "Setting the album image to the first image thumbnail #{firstThumbnail}."
        FileUtils.copy_file firstThumbnail, HIGHLIGHT
      end
    end

    def generate_header
      if @path.size > 1
	    navigation = %Q{
            <link rel="home" title="Home" href="#{navigate 'home'}" />
            <link rel="up" title="Up" href="#{navigate 'up', :level => 1}" />
        }
      end
      relative = Helper.relativise @path.size - 1
      @out << %Q{<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
        <head>            
            <meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
            <meta name="author" content="#{@opts[:author]}" />
            <meta name="generator" content="Rhotoalbum #{VERSION}" />
            <title>#{@opts[:title]} :: #{@path.last}</title>
            #{navigation}
            <link href="#{relative}#{@opts[:css]}" media="all" rel="stylesheet" type="text/css" />
            <link href="#{relative}rhotoalbum.css#" media="all" rel="alternate stylesheet" type="text/css" title="black"/>
            <link href="#{relative}rhotoalbum_w.css#" media="all" rel="alternate stylesheet" type="text/css" title="white"/>
        </head>
        <body>
        }
    end

    def generate_footer
      @out << Helper.copyright(@opts)
      @out <<%Q{
        </body>
        </html>
    }
    end

    def generate_body subdirs, images, texts
      generate_menu images, subdirs
      generate_subdirs subdirs, texts
      generate_images images, texts
    end

    def number_of_images images, talkative=true
      n = images.include?(HIGHLIGHT) ? images.size - 1 : images.size
      if n == 0
        talkative ? @opts[:labelNoPhoto] : ''
      elsif n == 1
        @opts[:labelOnePhoto]
      else
        @opts[:labelMorePhotos].gsub('#',n.to_s)
      end
    end

    def number_of_subalbums subalbums
      s = subalbums.size
      if s == 0
        ''
      elsif s == 1
        @opts[:labelOneAlbum]
      else
        @opts[:labelMoreAlbums].gsub('#',s.to_s)
      end
    end
  end

  # A thumbnails generator. It calls an external application to generate a thumbnail. Currently it is the <code>convert</code> application from the ImageMagick library.
  #
  class ThumbnailGenerator
    def initialize opts = {}
      @opts = opts
    end

    def thumbnail image
      Dir.mkdir THUMBNAILS_DIR unless File.exists? THUMBNAILS_DIR
      th = "#{THUMBNAILS_DIR}/#{thumbnail_name image}"
      generate th, image unless (File.exists? th) || (image == HIGHLIGHT )
      th
    end

    def thumbnail_name image
      "th_#{image}"
    end

    def generate thumbnail, image
      puts "Generating #{thumbnail} from #{image}"
      `convert "#{image}" -thumbnail #{@opts[:thumbnailDim]} -blur 0x0.25 "#{thumbnail}"`
    end
  end

  class ImageInfo
    def self.image_name image
      re = /.((jpg)|(jpeg)|(png)|(gif)|(tiff))$/i
      re.match image
      $`
    end

    def self.image_timestamp image
      EXIFR::JPEG.new(image).date_time
      # File.new(image).mtime.strftime '%A %d %B %Y %H:%M'
    end
  end

    class Generator
        IMAGE_MASK = '*.{jpg,JPG,jpeg,JPEG,png,PNG,gif,GIF}'
        DESCRIPTION_FILE = 'description.txt'
        def initialize opts = {}
          if opts
            @opts = DEFAULTS.merge opts
          else
            @opts = DEFAULTS
          end
          puts "Options: #{@opts.inspect}"
        end
    
        def execute cmd, path
            puts "Generating (#{cmd}) files in the directory: #{path.join '/'}"
            images = Dir[IMAGE_MASK].sort!
            # the images array contains also the HIGHLIGHT image, that is handled as needed later
            
            subdirs = Dir['*'].find_all do |d|
                File.directory?(d) and d != THUMBNAILS_DIR
            end
            subdirs.sort!
            
            case cmd 
                when 'generate' then generateAlbum path, subdirs, images
                when 'text' then generateText path, subdirs, images
                when 'cleanindex' then return cleanindex(path)
                when 'clean' then return clean(path)
            end
            #recursion
            subdirs.each do |subdir|
                Dir.chdir subdir
                execute cmd, path + [subdir]
                Dir.chdir '..' 
            end
        end
        
        def cleanindex aPath
            FileUtils.rm Dir['**/index.html'], :verbose=>true
        end
        def clean aPath
            FileUtils.rm_rf Dir['**/thumbnails'], :verbose=>true
            FileUtils.rm Dir['**/highlight.jpg'], :verbose=>true
            cleanindex aPath
        end
        
        def generateAlbum path, subdirs, images
            texts = loadTexts path, images, subdirs
            puts "Image descriptions: #{texts.inspect}"
            File.open('index.html', "w") do |out|
                pg = PageGenerator.new out, path, ScriptGenerator.new(@opts), ThumbnailGenerator.new(@opts), @opts
                pg.generate subdirs, images, texts
            end        
        end
        
        # Generates empty boilerplate central description file for images and albums (does not overwrite existing files)
        def generateText path, subdirs, images
            textables =subdirs+ images
            puts('The text description file already exist') or return if File.exist? DESCRIPTION_FILE
            File.open(DESCRIPTION_FILE, "w") do |out|
                out.puts '# Write descriptions for images and albums. Format: one definition per line, filename and text separated by colon, semicolon, comma or tab.'
                textables.each do |img|
                    out<<"#{img}\t\n"
                end
            end        
        end
        
        # Loads texts/descriptons for images and albums
        # Returns hash filename=>text
        def loadTexts path, images, subdirs
            texts = loadCentralTexts path
            texts.merge loadPerFileTexts(path, images, subdirs)
        end

        # Loads texts/descriptons for images and albums from central file 'description.,txt'
        # Format: one definition per line, filename and text separated by colon, semicolon, comma, or tab., Hash comments allowed
        # Returns hash: filename=>text
        def loadCentralTexts path
            #textFiles = Dir['*.{txt,TXT}']
            texts = {}
            if File.exist? DESCRIPTION_FILE
                File.open(DESCRIPTION_FILE) { |f| 
                    f.each {|l|
                        l.gsub!( /#.*$/,'' )  #remove comments
                        name,text=l.scan(/(.+?)\s*[;,:\t](.*)/).first
                        texts[name.to_s.strip]=text.to_s.strip if text.to_s.strip.size>0
                    }
                }
            end
            texts
        end
        
        # Loads texts/descriptons for image/album separate file
        # The filename that contain the text has format: #{image_or_album_fname}.txt
        # Returns hash: filename=>text
        def loadPerFileTexts path, images, subdirs
            texts = {}
            images.each do |fname|
                textfname="#{fname}.txt"
                if File.exist? textfname
                    text=File.open(textfname) {|f| f.read}
                    texts[fname]=text
                end
            end
            texts
        end


    end

  class Helper
    def self.relativise level
      relative = './'
      level.times do
        relative += '../'
      end

      relative
    end

    def self.copyright opts
        cp = opts[:copyright]
        cp = "All rights reserved."  unless cp
        cp = "#{opts[:author_label]} #{opts[:author]}<br />#{cp}"
        %Q{
    <div class="copyright">
    <p class="license">
        #{cp}
      </p>
      <p class="software">Generated by <a href="http://rhotoalbum.rubyforge.org/" title="Photo album generator"><em>Rhotoalbum</em>  - a photo album generator.</a></p>
      </div>
    }
    end

  end

  class Runtime 
    def go cmd = nil, opts = {} 
      Generator.new(opts).execute( cmd, ['.'] )
    end
  end
end

#If executed from command line
if __FILE__ == $0
    def symbolize aHash
        return unless aHash
        ih={}
        aHash.each {|n,v| ih[n.to_sym]=v}
        ih
    end
    
    cmd = (ARGV.shift or 'generate')
    #check cmd line
    puts('Usage: rhotoalbum.rb [ text | generate | clean | cleanindex | help]') or exit if cmd=~/help|-h/i or not RhotoAlbum::CMDS.include?(cmd) 
    puts "Rhotoalbum #{RhotoAlbum::VERSION}"
    puts "exifr library: #{EXIF_LIB ? '' : 'not '}found"
    #load options
    ext_opts=YAML.load_file RhotoAlbum::OPTIONS_FILE if File.exist? RhotoAlbum::OPTIONS_FILE
    puts "Command: #{cmd}, options.yml file #{ext_opts ? 'found' : 'not found'}" 
    #go for it
    RhotoAlbum::Runtime.new.go cmd, symbolize(ext_opts)
end

