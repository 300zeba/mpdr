import argparse

def create_instance(route_file):
    part1_file = open("TestMpdrC.part1.nc", "r")
    part2_file = open("TestMpdrC.part2.nc", "r")
    output_file = open("TestMpdrC.nc", "w")

    route_text = route_file.read();
    part1_text = part1_file.read();
    part2_text = part2_file.read();

    output_file.write(part1_text);
    output_file.write(route_text);
    output_file.write(part2_text);

    route_file.close()
    part1_file.close()
    part2_file.close()
    output_file.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--route-file", nargs="?",
                        type=argparse.FileType("r"), required=True)
    args = parser.parse_args()
    create_instance(args.route_file)

if __name__ == "__main__":
    main()
