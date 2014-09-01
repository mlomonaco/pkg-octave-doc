## Copyright (C) 2014 Julien Bect <julien.bect@supelec.fr>
## Copyright (C) 2008 Soren Hauberg <soren@hauberg.org>
##
## This program is free software; you can redistribute it and/or modify it
## under the terms of the GNU General Public License as published by
## the Free Software Foundation; either version 3 of the License, or (at
## your option) any later version.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
## General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with this program; see the file COPYING.  If not, see
## <http://www.gnu.org/licenses/>.

## -*- texinfo -*-
## @deftypefn {Function File} html_help_text (@var{name}, @var{outname}, @var{options})
## Writes a function help text to disk formatted as @t{HTML}.
##
## The help text of the function @var{name} is written to the file @var{outname}
## formatted as @t{HTML}. The design of the generated @t{HTML} page is controlled
## through the @var{options} variable. This is a structure with the following
## optional fields.
##
## @table @samp
## @item header
## This field contains the @t{HTML} header of the generated file. Through this
## things such as @t{CSS} style sheets can be set.
## @item footer
## This field contains the @t{HTML} footer of the generated file. This should
## match the @samp{header} field to ensure all opened tags get closed.
## @item title
## This field sets the title of the @t{HTML} page. This is enforced even if the
## @samp{header} field contains a title.
## @end table
##
## @var{options} structures for various projects can be with the @code{get_html_options}
## function. As a convenience, if @var{options} is a string, a structure will
## be generated by calling @code{get_html_options}.
##
## @seealso{get_html_options, generate_package_html}
## @end deftypefn

function html_help_text ...
  (name, outname, options = struct (), root = "", pkgroot = "", pkgname = "")
  
  ## Get the help text of the function
  [text, format] = get_help_text (name);
  text = insert_char_entities (text);
  
  ## If options is a string, call get_html_options
  if (ischar (options))
    options = get_html_options (options);
  endif
    
  ## Take action depending on help text format
  switch (lower (format))
    case "plain text"
      text = sprintf ("<pre>%s</pre>\n", text);
      
    case "texinfo"
      ## Add easily recognisable text before and after real text
      start = "###### OCTAVE START ######";
      stop  = "###### OCTAVE STOP ######";
      text = sprintf ("%s\n%s\n%s\n", start, text, stop);
      
      ## Handle @seealso
      if (isfield (options, "seealso"))
        seealso = @(args) options.seealso (root, args);
      else
        seealso = @(args) html_see_also_with_prefix (root, args {:});
      endif

      ## Run makeinfo
      [text, status] = __makeinfo__ (text, "html", seealso);
      if (status != 0)
        error ("html_help_text: couln't parse file '%s'", name);
      endif
      
      ## Extract the body of makeinfo's output
      start_idx = strfind (text, start);
      stop_idx = strfind (text, stop);
      header = text (1:start_idx - 1);
      text = text (start_idx + length (start):stop_idx - 1);
            
      ## Hack around 'makeinfo' bug that forgets to put <p>'s before function declarations
      text = strrep (text, "&mdash;", "<p class=\"functionfile\">");
            
    case "not found"
      error ("html_help_text: `%s' not found\n", name);
    otherwise
      error ("html_help_text: internal error: unsupported help text format: '%s'\n", format);
  endswitch

  ## Read 'options' input argument
  [header, title, footer] = get_header_title_and_footer ...
    ("function", options, name, root, pkgroot, pkgname);
  
  ## Add demo:// links if requested
  if (isfield (options, "include_demos") && options.include_demos)
    ## Determine if we have demos
    [code, idx] = test (name, "grabdemo");
    if (length (idx) > 1)
      ## Demos to the main text
      demo_text = "";
      
      outdir = fileparts (outname);
      imagedir = "images";
      full_imagedir = fullfile (outdir, imagedir);
      num_demos = length (idx) - 1;
      demo_num = 0;
      for k = 1:num_demos
        ## Run demo
        code_k = code (idx (k):idx (k+1)-1);
        try
          [output, images] = get_output (code_k, imagedir, full_imagedir, name);
        catch
          lasterr ()
          continue;
        end_try_catch
        has_text = !isempty (output);
        has_images = !isempty (images);
        if (length (images) > 1)
          ft = "figures";
        else
          ft = "figure";
        endif

        ## Create text
        demo_num ++;
        demo_header = sprintf ("<h2>Demonstration %d</h2>\n<div class=\"demo\">\n", demo_num);
        demo_footer = "</div>\n";
        
        demo_k {1} = "<p>The following code</p>\n";
        demo_k {2} = sprintf ("<pre class=\"example\">%s</pre>\n", code_k);
        if (has_text && has_images)
          demo_k {3} = "<p>Produces the following output</p>\n";
          demo_k {4} = sprintf ("<pre class=\"example\">%s</pre>\n", output);
          demo_k {5} = sprintf ("<p>and the following %s</p>\n", ft);
          demo_k {6} = sprintf ("<p>%s</p>\n", images_in_html (images));
        elseif (has_text) # no images
          demo_k {3} = "<p>Produces the following output</p>\n";
          demo_k {4} = sprintf ("<pre class=\"example\">%s</pre>\n", output);        
        elseif (has_images) # no text
          demo_k {3} = sprintf ("<p>Produces the following %s</p>\n", ft);
          demo_k {6} = sprintf ("<p>%s</p>\n", images_in_html (images));
        else # neither text nor images
          demo_k {3} = sprintf ("<p>gives an example of how '%s' is used.</p>\n", name);
        endif
        
        demo_text = strcat (demo_text, demo_header, demo_k {:}, demo_footer);
      endfor
      
      text = strcat (text, demo_text);
    endif
  endif
  
  ## Write result to disk
  fid = fopen (outname, "w");
  if (fid < 0)
    error ("html_help_text: could not open '%s' for writing", outname);
  endif
  fprintf (fid, "%s\n%s\n%s", header, text, footer);
  fclose (fid);

endfunction

function expanded = html_see_also_with_prefix (prefix, root, varargin)
  header = "@html\n<div class=\"seealso\">\n<b>See also</b>: ";
  footer = "\n</div>\n@end html\n";
  
  format = sprintf (" <a href=\"%s%%s.html\">%%s</a> ", prefix);
  
  varargin2 = cell (1, 2*length (varargin));
  varargin2 (1:2:end) = varargin;
  varargin2 (2:2:end) = varargin;
  
  list = sprintf (format, varargin2 {:});
  
  expanded = strcat (header, list, footer);
endfunction

function [text, images] = get_output (code, imagedir, full_imagedir, fileprefix)
  ## Clear everything
  close all
  diary_file = "__diary__.txt";
  if (exist (diary_file, "file"))
    delete (diary_file);
  endif
  
  unwind_protect
    ## Setup figure and pager properties
    def = get (0, "defaultfigurevisible");
    set (0, "defaultfigurevisible", "off");
    more_val = page_screen_output (false);
  
    ## Evaluate the code
    diary (diary_file);
    eval (code);
    diary ("off");
  
    ## Read the results
    fid = fopen (diary_file, "r");
    diary_data = char (fread (fid).');
    fclose (fid);

    ## Remove 'diary ("off");' from the diary
    idx = strfind (diary_data, "diary (\"off\");");
    if (isempty (idx))
      text = diary_data;
    else
      text = diary_data (1:idx (end)-1);
    endif
    text = strtrim (text);
  
    ## Save figures
    if (!isempty (get (0, "currentfigure")) && !exist (full_imagedir, "dir"))
      mkdir (full_imagedir);
    endif
  
    images = {};
    while (!isempty (get (0, "currentfigure")))
      fig = gcf ();
      r = round (1000*rand ());
      name = sprintf ("%s_%d.png", fileprefix, r);
      full_filename = fullfile (full_imagedir, name);
      filename = fullfile (imagedir, name);
      print (fig, full_filename);
      images {end+1} = filename;
      close (fig);
    endwhile
  
    ## Reverse image list, since we got them latest-first
    images = images (end:-1:1);

  unwind_protect_cleanup
    delete (diary_file);
    set (0, "defaultfigurevisible", def);
    page_screen_output (more_val);
  end_unwind_protect
endfunction

function text = images_in_html (images)
  header = "<table class=\"images\">\n<tr>\n";
  footer = "</tr></table>\n";
  headers = sprintf ("<th class=\"images\">Figure %d</th>\n", 1:numel (images));
  ims = sprintf ("<td class=\"images\"><img src=\"%s\" class=\"demo\"/></td>\n", images {:});
  text = strcat (header, headers, "</tr><tr>\n", ims, footer);
endfunction
