#ifndef ERROR_PARSER_HPP
#define ERROR_PARSER_HPP

#include <cctype>
#include <cstring>
#include <optional>
#include <string>
#include <string_view>

class ErrorParser
{
public:
    struct ParsedError
    {
        std::string_view filename;
        std::optional<int> line_number;
        std::string_view message;
    };

    static ParsedError parse(const char* error_str)
    {
        ParsedError result;

        if (!error_str)
        {
            return result;
        }

        // Skip leading whitespace
        while (*error_str && isspace(*error_str))
        {
            ++error_str;
        }

        if (!*error_str)
        {
            return result;
        }

        // Find first colon (guaranteed to exist)
        const char* first_colon = std::strchr(error_str, ':');
        if (!first_colon)
        {
            // Fallback: treat entire string as error message
            result.message = std::string_view(error_str);
            return result;
        }

        // Extract filename
        result.filename = std::string_view(error_str, first_colon - error_str);

        // Find second colon (guaranteed to exist)
        const char* second_colon = std::strchr(first_colon + 1, ':');
        if (!second_colon)
        {
            // Fallback: treat everything after first colon as error message
            result.message = std::string_view(first_colon + 1);
            return result;
        }

        // Extract line number
        const char* line_start = first_colon + 1;
        const char* line_end = second_colon;

        // Skip whitespace around line number
        while (line_start < line_end && isspace(*line_start))
            ++line_start;
        while (line_end > line_start && isspace(*(line_end - 1)))
            --line_end;

        if (line_start < line_end)
        {
            int line_num = 0;
            bool has_digits = false;
            for (const char* p = line_start; p < line_end; ++p)
            {
                if (isdigit(*p))
                {
                    line_num = line_num * 10 + (*p - '0');
                    has_digits = true;
                }
                else if (!isspace(*p))
                {
                    break; // Stop at first non-digit, non-whitespace
                }
            }
            if (has_digits)
            {
                result.line_number = line_num;
            }
        }

        // Extract error message
        const char* msg_start = second_colon + 1;
        while (*msg_start && isspace(*msg_start))
        {
            ++msg_start;
        }
        result.message = std::string_view(msg_start);

        return result;
    }
};

#endif // ERROR_PARSER_HPP
