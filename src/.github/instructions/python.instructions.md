---
applyTo: "**/*.py"
---
# Python Instructions for Apik CVDL Odoo Projects
---

## Python Instructions

- Write clear and concise comments for each function.
- Ensure functions have descriptive names and include type hints.
- Use the `typing` module for type annotations (e.g., `List[str]`, `Dict[str, int]`).
- Break down complex functions into smaller, more manageable functions.
- Add docstrings to functions and classes; docstrings must be in English and follow the Google style convention.
- Prefer modern Python 3.10+ syntax.
- Limit to features up to Python 3.12.

## General Instructions

- Always prioritize readability and clarity.
- For algorithm-related code, include explanations of the approach used.
- Write code with good maintainability practices, including comments on why certain design decisions were made.
- Handle edge cases and write clear exception handling.
- For libraries or external dependencies, mention their usage and purpose in comments.
- Write concise, efficient, and idiomatic code that is also easily understandable.

## Naming Conventions

- Use snake_case for all functions, variables, and file names.
- Use PascalCase for classes.
- Use consistent naming conventions and follow language-specific best practices.
- Use English for all names and comments.

## Code Style and Formatting

- Follow the **PEP 8** style guide for Python.
- Maintain proper indentation (use 4 spaces for each level of indentation).
- Ensure lines do not exceed 79 characters.
- Place function and class docstrings immediately after the `def` or `class` keyword.
- Use blank lines to separate functions, classes, and code blocks where appropriate.
- Use f-strings for string formatting.


## Edge Cases and Testing

- Always include test cases for critical paths of the application.
- Account for common edge cases like empty inputs, invalid data types, and large datasets.
- Include comments for edge cases and the expected behavior in those cases.

## Example of Proper Documentation

```python
def calculate_area(radius: float) -> float:
    """
    Calculate the area of a circle given the radius.
    
    Args:
        radius (float): The radius of the circle.
    
    Returns:
        float: The area of the circle, calculated as π * radius^2.

    Raises:
        ValueError: If the radius is negative.
    """
    import math
    if radius < 0:
        raise ValueError("Radius must be non-negative")
    return math.pi * radius ** 2
```

## Supplementary Codestyle

- Use list comprehensions when possible.
- Avoid and remove unused global imports.
- Use context managers (`with` statement) for file handling.
- Avoid unnecessary or obvious comments.
- Document and add dependencies in the `requirements.txt` file.
- Use efficient string joining, such as `str.join()`, to concatenate multiple strings.
- Use appropriate data structures (lists, tuples, sets, dictionaries) as needed.
- Use assertions to check conditions that should always be true.

## Odoo Specific Guidelines

- Follow Odoo's and OCA coding guidelines and best practices.
- Use Odoo's built-in models and fields whenever possible.
- Leverage Odoo's ORM features for database interactions.
- Use logging modules like `logging` instead of `print()` for debug and info messages, must use ```python
_logger = logging.getLogger(__name__)
```.
