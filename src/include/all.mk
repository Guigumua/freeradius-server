#
# Version:	$Id$
#

#
#  Build dynamic headers by substituting various values from autoconf.h, these
#  get installed with the library files, so external programs can tell what
#  the server library was built with.
#
#  The RFC headers are dynamic, too.
#
#  The rest of the headers are static.
#
HEADERS_DY	:= features.h missing.h radpaths.h

HEADERS	= \
	build.h \
	$(HEADERS_DY)


#
#  Solaris awk doesn't recognise [[:blank:]] hence [\t ]
#
src/include/autoconf.sed: src/include/autoconf.h
	${Q}grep ^#define $< | sed 's,/\*\*/,1,;' | awk '{print "'\
	's,#[\\t ]*ifdef[\\t ]*" $$2 "$$,#if "$$3 ",g;'\
	's,#[\\t ]*ifndef[\\t ]*" $$2 "$$,#if !"$$3 ",g;'\
	's,defined(" $$2 ")," $$3 ",g;"}' > $@
	${Q}grep -o '#undef [^ ]*' $< | sed 's,/#undef /,,;' | awk '{print "'\
	's,#[\\t ]*ifdef[\\t ]*" $$2 "$$,#if 0,g;'\
	's,#[\\t ]*ifndef[\\t ]*" $$2 "$$,#if 1,g;'\
	's,defined(" $$2 "),0,g;"}' >> $@


######################################################################
#
#  Create the header files from the dictionaries.
#

# Find the RFC dictionaries, and add them to the list to be converted
DICT := $(wildcard $(addsuffix /dictionary.rfc*,$(addprefix share/dictionary/,$(PROTOCOLS))))

# Find internal dictionaries and add them to the list to be converte
DICT += $(wildcard $(addsuffix /dictionary.freeradius*,$(addprefix share/dictionary/,$(PROTOCOLS))))

# These contain the protocol number definitions
DICT += $(wildcard $(addsuffix /dictionary,$(addprefix share/dictionary/,$(PROTOCOLS))))

# Add in protocol specific dictionaries (should be done in proto_* modules?)
DICT += share/dictionary/vmps/dictionary.vmps
DICT += share/dictionary/tacacs/dictionary.tacacs

NORMALIZE	:= tr -- '[:lower:]/+.-' '[:upper:]____' | sed 's/241_//;'
HEADER		:= "/* AUTO_GENERATED FILE.  DO NOT EDIT */"

#  Build targets dynamically
define DICT_TO_HEADER
HEADERS_DY += $(1)
src/include/$(1): $(2)
	${Q}$$(ECHO) HEADER $$(patsubst src/include/%,%,$$@)
	${Q}test -e $$@ || mkdir -p $$(dir $$@)
	${Q}echo "#pragma once" > $$@
	${Q}grep ^PROTOCOL $$< | ${NORMALIZE} | awk '{print "#define FR_PROTOCOL_"$$$$2" " $$$$3 "	//!< AUTOGENERATED PROTOCOL NUMBER DEFINITION"}' >> $$@
	${Q}grep ^ATTRIBUTE $$< | ${NORMALIZE} | awk '{print "#define FR_"$$$$2 " " $$$$3 "	//!< AUTOGENERATED ATTRIBUTE DEFINITION"}' >> $$@
	${Q}grep ^VALUE $$< | ${NORMALIZE} | awk '{print "#define FR_"$$$$2"_VALUE_"$$$$3 " " $$$$4 "	//!< AUTOGENERATED VALUE DEFINITION"}' >> $$@
endef
$(foreach x,$(DICT),$(eval $(call DICT_TO_HEADER,$(addsuffix .h,$(subst dictionary.,,$(patsubst share/dictionary/%,protocol/%,$(x)))),$(x))))

.PHONY: src/include/protocol
src/include/protocol:
	${Q}mkdir -p $@

HEADERS_DY += protocol/base.h

src/include/protocol/base.h: $(wildcard share/dictionary/*/dictionary) $(wildcard share/dictionary/eap/*/dictionary) | src/include/protocol
	@echo HEADER $(patsubst src/include/%,%,$@)
	${Q}echo "#pragma once" > $@
	${Q}for X in $^; do grep ^PROTOCOL $$X | ${NORMALIZE} | awk '{print "#define FR_PROTOCOL_"$$2" " $$3 "	//!< AUTOGENERATED PROTOCOL NUMBER DEFINITION"}' >> $@; done


#  Add our dynamic headers to the header manifest so they get
#  installed.
#HEADERS += $(HEADERS_DY)

#  Build features.h by copying over WITH_* and RADIUSD_VERSION_*
#  preprocessor macros from autoconf.h
#  This means we don't need to include autoconf.h in installed headers.
#
#  We use simple patterns here to work with the lowest common
#  denominator's grep (Solaris).
#
src/include/features.h: src/include/features-h src/include/autoconf.h
	@$(ECHO) HEADER $@
	${Q}echo "#pragma once" > $@
	${Q}cat $< >> $@
	${Q}grep "^#define[ ]*WITH_" src/include/autoconf.h >> $@
	${Q}grep "^#define[ ]*RADIUSD_VERSION" src/include/autoconf.h >> $@
#
#  Use the SED script we built earlier to make permanent substitutions
#  of definitions in missing-h to build missing.h
#
src/include/missing.h: src/include/missing-h src/include/autoconf.sed
	@$(ECHO) HEADER $@
	${Q}sed -f src/include/autoconf.sed < $< > $@

src/include/radpaths.h: src/include/build-radpaths-h
	@$(ECHO) HEADER $@
	${Q}cd src/include && /bin/sh build-radpaths-h

#
#  Create the soft link for the fake include file paths.
#
src/freeradius-devel:
	@echo LN-SF src/include src/freeradius-devel
	${Q}[ -e $@ ] || ln -s include $@

#
#  Ensure we set up the build environment
#
BOOTSTRAP_BUILD += src/freeradius-devel $(addprefix src/include/,$(HEADERS_DY)) $(HEADERS_RFC)
scan: $(BOOTSTRAP_BUILD)

#
#  Regenerate the headers if we re-run autoconf.
#  This is to that changes to the build rules (e.g. PW_FOO -> FR_FOO)
#  result in the headers being rebuilt.
#

# define the installation directory
SRC_INCLUDE_DIR := ${R}${includedir}/freeradius

$(SRC_INCLUDE_DIR):
	${Q}$(INSTALL) -d -m 755 ${SRC_INCLUDE_DIR}

#
#  install the headers by re-writing the local files
#
#  install-sh function for creating directories gets confused
#  if there's a trailing slash, tries to create a directory
#  it already created, and fails...
#
${SRC_INCLUDE_DIR}/%.h: src/include/%.h | $(SRC_INCLUDE_DIR)
	@echo INSTALL $(subst src/include,freeradius-server,$<)
	${Q}$(INSTALL) -d -m 755 `echo $(dir $@) | sed 's/\/$$//'`
# Expression must deal with indentation after the hash and copy it to the substitution string.
# Hash not anchored to allow substitution in function documentation.
	${Q}sed -e 's/#\([\\t ]*\)include <freeradius-devel\/\([^>]*\)>/#\1include <freeradius\/\2>/g' < $< > $@
	${Q}chmod 644 $@

all: $(addprefix src/include/,$(HEADERS_DY))

install.src.include: $(addprefix ${SRC_INCLUDE_DIR}/,${HEADERS})
install: install.src.include

#
#  Cleaning
#
.PHONY: clean.src.include distclean.src.include
clean.src.include:
	${Q}rm -rf $(addprefix src/include/,$(HEADERS_DY))

clean: clean.src.include

distclean.src.include: clean.src.include
	${Q}rm -f autoconf.sed
	${Q}rm -rf src/include/protocol

distclean: distclean.src.include

