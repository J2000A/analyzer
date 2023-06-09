import argparse
import os
import shutil
import sys
import questionary
import yaml
from pathlib import Path
from util.util import *
from util.generate_programs import gernerate_programs
from util.generate_tests import generate_tests
from util.run_tests import run_tests
from generators.generate_mutations import add_mutation_options, get_mutations_from_args

logo = '''
         __  __       _        _   _                    
        |  \/  |     | |      | | (_)                   
        | \  / |_   _| |_ __ _| |_ _  ___  _ __         
        | |\/| | | | | __/ _` | __| |/ _ \| '_ \        
        | |  | | |_| | || (_| | |_| | (_) | | | |       
        |_|  |_|\__,_|\__\__,_|\__|_|\___/|_| |_|       
          _____                           _             
         / ____|                         | |            
        | |  __  ___ _ __   ___ _ __ __ _| |_ ___  _ __ 
        | | |_ |/ _ \ '_ \ / _ \ '__/ _` | __/ _ \| '__|
        | |__| |  __/ | | |  __/ | | (_| | || (_) | |   
         \_____|\___|_| |_|\___|_|  \__,_|\__\___/|_|   
                                                        
                                                        

        '''

def run(goblint_path, llvm_path, input_path, is_mutation, is_ml, is_git, mutations, create_precision, is_run_tests, api_key_path, ml_count):
    # Make paths absolute
    goblint_path = os.path.abspath(os.path.expanduser(goblint_path))
    llvm_path = os.path.abspath(os.path.expanduser(llvm_path))
    input_path = os.path.abspath(os.path.expanduser(input_path)) #TODO Handle git url

    # Generate the programs
    goblint_executable_path = os.path.join(goblint_path, 'goblint')
    clang_tidy_path = os.path.join(llvm_path, 'build', 'bin', 'clang-tidy')
    temp_path = os.path.abspath(os.path.join(os.path.curdir, 'temp'))
    gernerate_programs(input_path, temp_path, clang_tidy_path, goblint_executable_path, api_key_path, mutations, is_mutation, is_ml, is_git, ml_count)

    # Run tests
    if is_run_tests:
        test_path = os.path.abspath(os.path.join(os.path.curdir, '99-temp'))
        if create_precision:
            print(SEPERATOR)
            print(f'Writing out {COLOR_BLUE}PRECISION TEST{COLOR_RESET} files for running:')
            generate_tests(temp_path, test_path, precision_test=True)
            run_tests(test_path, goblint_path, cfg=True) #TODO Add Option for cfg
        print(SEPERATOR)
        print(f'Writing out {COLOR_BLUE}CORRECTNESS TEST{COLOR_RESET} files for running:')
        generate_tests(temp_path, test_path, precision_test=False)
        run_tests(test_path, goblint_path, cfg=True) #TODO Add Option for cfg
        if os.path.exists(test_path):
            shutil.rmtree(test_path)

    #TODO Print link to html result and give summary

    #Write out custom test files
    print(SEPERATOR)
    correctness_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '99-test')
    print(f'Writing out {COLOR_BLUE}CUSTOM CORRECTNESS TEST{COLOR_RESET} files:')
    generate_tests(temp_path, correctness_path, precision_test=False) #TODO Custom name
    print(f'{COLOR_GREEN}Test stored in the directory: {correctness_path}{COLOR_RESET}') #TODO Multiple directories?!
    if create_precision:
        print(SEPERATOR)
        precision_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "98-precision")
        print(f'Writing out {COLOR_BLUE}CUSTOM PRECISION TEST{COLOR_RESET} files:')
        generate_tests(temp_path, precision_path, precision_test=False) #TODO Custom name
        print(f'{COLOR_GREEN}Test stored in the directory: {precision_path}{COLOR_RESET}') #TODO Multiple directories?!

def cli(enable_mutations, enable_ml, enable_git, mutations, precision, running, input, ml_count):
    # Check config file
    config_path = Path(CONFIG_FILENAME)
    config = {}
    if not config_path.is_file():
        print(f'Config file "{config_path}" not found. Please provide the paths:')
        goblint_path = questionary.text('Enter the path to the goblint repository: ', default="~/Goblint-Repo/analyzer").ask()
        llvm_path = questionary.text('Enter the path to the llvm repository with the modified clang-tidy: ', default="~/Clang-Repo/llvm-project").ask()
        config.update({CONFIG_GOBLINT: goblint_path, CONFIG_LLVM: llvm_path, CONFIG_LAST_INPUT_MUTATION: '', CONFIG_LAST_INPUT_GIT: ''})
        last_input_mutation = ''
        last_input_git = ''
        with open(config_path, 'w') as outfile:
            yaml.dump(config, outfile)
    else:
        with open(config_path, 'r') as stream:
            config = yaml.safe_load(stream)
            goblint_path = config[CONFIG_GOBLINT]
            llvm_path = config[CONFIG_LLVM]
            last_input_mutation = config[CONFIG_LAST_INPUT_MUTATION]
            last_input_git = config[CONFIG_LAST_INPUT_GIT]
            print(f'Using goblint-path (change in ./{CONFIG_FILENAME}): {goblint_path}')
            print(f'Using llvm-path (change in ./{CONFIG_FILENAME}): {llvm_path}')

    # Handle Questions
    if not (enable_mutations or enable_ml or enable_git):
        while True:
            generators = questionary.checkbox(
                'Select one or more generator types (When git is checked no other can be checked!):',
                choices=[
                    questionary.Choice('Mutations', checked=True),
                    'ML',
                    'Git'
                ]).ask()

            # check if 'Git' is selected along with other options
            if 'Git' in generators and len(generators) > 1:
                print(f"{COLOR_RED}If 'Git' is selected, no other options should be selected. Please select again.{COLOR_RESET}")
                continue
            else:
                break

        enable_mutations = 'Mutations' in generators
        enable_ml = 'ML' in generators
        enable_git = 'Git' in generators
        
        if enable_mutations:
            selected_mutations = questionary.checkbox(
            'Select one or more mutation types:',
            choices=[
                questionary.Choice('remove-function-body (RFB)', checked=True),
                questionary.Choice('unary-operator-inversion (UOI)', checked=True),
                questionary.Choice('relational-operator-replacement (ROR)', checked=True),
                questionary.Choice('constant-replacement (CR)', checked=True),
                questionary.Choice('remove-thread (RT)', checked=True),
                questionary.Choice('logical-connector-replacement (LCR)', checked=True),
            ]).ask()
            mutations = Mutations(
                rfb='remove-function-body (RFB)' in selected_mutations,
                uoi='unary-operator-inversion (UOI)' in selected_mutations,
                ror='relational-operator-replacement (ROR)' in selected_mutations,
                cr='constant-replacement (CR)' in selected_mutations,
                rt='remove-thread (RT)' in selected_mutations,
                lcr='logical-connector-replacement (LCR)' in selected_mutations
            )
    
    # Check for API Key
    if enable_ml:
        key_path = Path(APIKEY_FILENAME)
        key_data = {}
        if not key_path.is_file():
            print(f'Api key file "{key_path}" for OpenAi not found. Please provide the informations:')
            print('Be aware that the information is stored unencrypted. Do not remove the file from .gitignore!')
            print('Create an account here: https://openai.com/blog/openai-api')
            print('Create an API Key here: https://platform.openai.com/account/api-keys')
            print('Get your organization id here: https://platform.openai.com/account/org-settings')
            key = questionary.text('Enter the api key:').ask()
            org = questionary.text('Enter the organisation id:').ask()
            key_data.update({APIKEY_APIKEY: key, APIKEY_ORGANISATION: org})
            with open(key_path, 'w') as outfile:
                yaml.dump(key_data, outfile)
        else:
            with open(key_path, 'r') as stream:
                key_data = yaml.safe_load(stream)
                key = key_data[APIKEY_APIKEY]
                org = key_data[APIKEY_ORGANISATION]
                print(f'Using api-key for ML (change in ./{APIKEY_FILENAME}): ...{key[-4:]}')
                print(f'Using organisation id for ML (change in ./{APIKEY_FILENAME}): ...{org[-4:]}')
        key_path = os.path.abspath(key_path)
    else:
        key_path = None

    if enable_ml and ml_count == None:
        while True:
            ml_count = questionary.text('How many different programs should be generated with ML?', default=str(DEFAULT_ML_COUNT)).ask()
            if not ml_count.strip('\n').isdigit():
                print(f"{COLOR_RED}Please enter a valid number.{COLOR_RESET}")
                continue
            ml_count = int(ml_count.strip('\n'))
            if ml_count <= 0:
                print(f"{COLOR_RED}Please enter a number greater zero.{COLOR_RESET}")
                continue
            break

    if precision == None:
        precision = questionary.confirm('Create precision test files?', default=False).ask()

    if running == None:
        running = questionary.confirm('Run the tests?').ask()

    if input == None:
        while True:
            if enable_mutations or enable_ml:
                input = questionary.text('Enter the path to the c program for the mutations: ', default=last_input_mutation).ask()
                config.update({CONFIG_LAST_INPUT_MUTATION: input})
            else:
                input = questionary.text('Enter the path to the sh script with informations about the git repository (Use [-s] to see the template script ): ', default=last_input_git).ask()
                config.update({CONFIG_LAST_INPUT_GIT: input})
            if not os.path.exists(input):
                print(f"{COLOR_RED}Please enter a valid path.{COLOR_RESET}")
                continue
            with open(config_path, 'w') as outfile:
                yaml.dump(config, outfile)
            break

    run(goblint_path, llvm_path, input, enable_mutations, enable_ml, enable_git, mutations, precision, running, key_path, ml_count)


if __name__ == "__main__":
    print(f'{COLOR_YELLOW}Use [-h] to see the command line options{COLOR_RESET}')
    print(logo)

    parser = argparse.ArgumentParser(description='Generates mutations for creating incremental tests')
    parser.add_argument('-m', '--enable-mutations', action='store_true', help='Enable Mutations. When no mutation is selected all are activated.')
    parser.add_argument('-o', '--enable-ml', action='store_true', help='Enable ML')
    parser.add_argument('-g', '--enable-git', action='store_true', help='Enable Git')
    parser.add_argument('-ep', '--enable-precision', action='store_true', help='Enable Precision Tests')
    parser.add_argument('-dp', '--disable-precision', action='store_true', help='Disable Precision Tests')
    parser.add_argument('-er', '--enable-running', action='store_true', help='Enable Running Tests')
    parser.add_argument('-dr', '--disable-running', action='store_true', help='Disable Running Tests')
    parser.add_argument('-i', '--input', help='Input File')
    
    # Add mutation options
    add_mutation_options(parser)

    # Add ML options
    parser.add_argument('-c', '--ml-count', type=int, default=-1,  help='How many different programs should be generated with ML?')

    # Add GIT options
    parser.add_argument('-s', '--template-script', action='store_true', help='Print the template script for git repositories')

    args = parser.parse_args()

    if args.template_script:
        template_path = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'generators', 'generate_git_build_USER_INFO_TEMPLATE.sh'))
        print(f'{COLOR_YELLOW}Template can be found at: {template_path}{COLOR_RESET}')
        print('')
        with open(template_path, 'r') as file:
            content = file.read()
        print(content)
        print('')
        sys.exit(0)

    if args.enable_mutations or args.enable_ml or args.enable_git:
        # If using git, only git can be used
        if args.enable_git and (args.enable_ml or args.enable_mutations):
            parser.error("--enable-git cannot be used with --enable-ml or --enable-mutations")

        # If all mutation options are false, set all to true
        mutations = get_mutations_from_args(args)
        non_str_attributes = [attr for attr in vars(mutations) if not attr.endswith('_s')]
        if all(getattr(mutations, attr) is False for attr in non_str_attributes):
            mutations = Mutations(True, True, True, True, True, True)
    else:
        args.enable_mutations = None
        args.enable_ml = None
        args.enable_git = None
        mutations = None

    if args.enable_precision or args.disable_precision:
        # Only one can be selected
        if args.enable_precision and args.disable_precision:
            parser.error('Precision can not be enabled AND diabled')
        precision = args.enable_precision
    else:
        precision = None

    if args.enable_running or args.disable_running:
        # Only one can be selected
        if args.enable_running and args.disable_running:
            parser.error('Running can not be enabled AND diabled')
        running = args.enable_running
    else:
        running = None

    if args.ml_count > 0:
        ml_count = args.ml_count
    else:
        ml_count = None
    

    cli(args.enable_mutations, args.enable_ml, args.enable_git, mutations, precision, running, args.input, ml_count)