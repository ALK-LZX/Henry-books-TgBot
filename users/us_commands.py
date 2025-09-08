from aiogram import types
from aiogram import F
from kbs.kbs_user import *
import random
import json
from db.database import (
    get_number, save_number, increment_total_books,
    add_to_favorites, is_in_favorites
)
from users.personalization import maybe_add_phrase_mood, build_about, maybe_add_greeting, FIRST_BOOK_PHRASES
from users.favorites_commands import register_favorites_handlers

CATEGORY_MAP = {
    'usmorning': 'утреннее',
    'usday': 'дневное', 
    'usevening': 'вечернее',
    'usnight': 'ночное',
    'usmorning_prev': 'утреннее',
    'usday_prev': 'дневное',
    'usevening_prev': 'вечернее',
    'usnight_prev': 'ночное',
    'add_fav_morning': 'утреннее',
    'add_fav_day': 'дневное',
    'add_fav_evening': 'вечернее',
    'add_fav_night': 'ночное'
}

async def choosing_book(callback: types.CallbackQuery):
    greeting_text = ''
    if random.randint(1, 100) <=30:
        greeting = maybe_add_greeting(callback.from_user.id)
        if greeting:
            greeting_text = f'{greeting} '
    await callback.message.edit_text(f'{greeting_text}Итак, желаете почитать?', reply_markup=kb_uschoice)
    await callback.answer()

async def choosing_book2(callback: types.CallbackQuery):
    user_id = callback.from_user.id
    
    for category in ['утреннее', 'дневное', 'вечернее', 'ночное']:
        save_number(user_id, category, 0)
    
    await callback.message.edit_text('Прекрасно понимаю, милая душа. Какое у Вас настроение?', reply_markup=kb_bookchoice)
    await callback.answer() 

async def cancel_choice(callback: types.CallbackQuery):
    await callback.message.edit_text('Возможно, в другой раз.', reply_markup=kb_start)
    await callback.answer()

async def learning_more (callback: types.CallbackQuery):
    about = build_about()
    await callback.message.edit_text(about, reply_markup = kb_nazad)
    await callback.answer()

# async def show_art(callback: types.CallbackQuery):
#     rare_art = ['1st.jpg', '2nd.jpg', '3rd.jpg']
#     index = random.randint(0, 2)
#     file = rare_art[index]

#     try:
#         await callback.message.delete()
#         photo = FSInputFile(f'arts/{file}')
#         photo_message = await callback.message.answer_photo(photo=photo)
#         await callback.answer()
#         await asyncio.sleep(10)
#         await photo_message.delete()
#         await callback.message.answer(
#            'Я ждал Вас, человек. Чего же ждете Вы?', 
#             reply_markup=rand_startkb()
#         )
#     except Exception as e:
#         await callback.message.answer(f"Извините, арт временно недоступен... {file}")
#         await callback.answer()   


def get_books_sutki(time_period):
    try:
        with open('db/all_books.json', 'r', encoding='utf-8') as file:
            books = json.load(file)
        return books.get(time_period, [])
    except:
        return []

async def show_books(callback: types.CallbackQuery):
    user_id = callback.from_user.id
    
    config = {
        'usmorning': {
            'category': 'утреннее',
            'end_text': 'Не спешите. Возможно, дадите шанс чему-то из уже предложенной литературы?',
            'keyboard': kb_again_morning
        },
        'usday': {
            'category': 'дневное', 
            'end_text': 'По дневной тематике пока что завершаю предложения, милая душа.',
            'keyboard': kb_again_day
        },
        'usevening': {
            'category': 'вечернее',
            'end_text': 'Кхм. Вы весьма настойчивы... Думаю, пока что достаточно, не находите?',
            'keyboard': kb_again_evening
        },
        'usnight': {
            'category': 'ночное',
            'end_text': 'Книги ночи заслуживают внимательного отношения... А потому я предложу что-то новое лишь позже.',
            'keyboard': kb_again_night
        }
    }
    
    current_config = config[callback.data]
    category = CATEGORY_MAP[callback.data]
    books = get_books_sutki(category)

    if books:
        current_index = get_number(user_id, category)

        if current_index >= len(books):
            text = current_config['end_text']
            save_number(user_id, category, 0)
            reply_markup = kb_nazad
        else:
            book = books[current_index]
            mood_phrase = maybe_add_phrase_mood(category)
            if mood_phrase is None:
                mood_phrase = ''
            text = f'{mood_phrase}Для вашего настроения могу предложить вот такой вариант:\n{book["название"]}\n{book["автор"]}\n\n{book["описание"]}\n\n'
            save_number(user_id, category, current_index + 1)
            increment_total_books(user_id)
            reply_markup = current_config['keyboard']

        try:
            await callback.message.edit_text(text, reply_markup=reply_markup)
        except:
            pass
    else:
        text = 'Кажется, кто-то украл все книги. Скандал.'
        try:
            await callback.message.edit_text(text, reply_markup=kb_nazad)
        except:
            pass
    await callback.answer()


async def show_books_prev(callback: types.CallbackQuery):
    user_id = callback.from_user.id

    config = {
        'usmorning_prev': {
            'category': 'утреннее',
            'first_book_kb': kb_first_book_morning,
            'normal_kb': kb_again_morning
        },
        'usday_prev': {
            'category': 'дневное',
            'first_book_kb': kb_first_book_day, 
            'normal_kb': kb_again_day
        },
        'usevening_prev': {
            'category': 'вечернее',
            'first_book_kb': kb_first_book_evening,
            'normal_kb': kb_again_evening
        },
        'usnight_prev': {
            'category': 'ночное',
            'first_book_kb': kb_first_book_night,
            'normal_kb': kb_again_night
        }
    }
    
    current_config = config[callback.data]
    category = CATEGORY_MAP[callback.data]
    books = get_books_sutki(category)

    if books:
        current_index = get_number(user_id, category)
        if current_index <= 1:
            text = random.choice(FIRST_BOOK_PHRASES)
            try:
                await callback.message.edit_text(text, reply_markup=current_config['first_book_kb'])
            except:
                pass
            await callback.answer()
            return
            
        current_index = max(0, current_index - 2)
        book = books[current_index]
        mood_phrase = maybe_add_phrase_mood(category)
        if mood_phrase is None:
            mood_phrase = ''
        text = f'{mood_phrase}Для вашего настроения могу предложить вот такой вариант:\n{book["название"]}\n{book["автор"]}\n\n{book["описание"]}\n\n'
        save_number(user_id, category, current_index + 1)
        reply_markup = current_config['normal_kb']
        try:
            await callback.message.edit_text(text, reply_markup=reply_markup)
        except:
            pass
    else:
        text = 'Кажется, кто-то украл все книги. Скандал.'
        try:
            await callback.message.edit_text(text, reply_markup=kb_nazad)
        except:
            pass
    await callback.answer()


async def add_book_to_favorites(callback: types.CallbackQuery):
    user_id = callback.from_user.id

    category = CATEGORY_MAP[callback.data]
    books = get_books_sutki(category)
    current_index = get_number(user_id, category)
    
    if not books:
        await callback.answer('Ошибка: список книг пуст.')
        return
        
    if current_index <= 0:
        await callback.answer('Ошибка: книга не найдена.')
        return
        
    if current_index - 1 >= len(books):
        await callback.answer('Ошибка: индекс книги выходит за пределы списка.')
        return
    
    book = books[current_index - 1]
    
    if is_in_favorites(user_id, book['название'], book['автор']):
        await callback.answer('Уже в избранном.')
        return

    add_to_favorites(
        user_id=user_id,
        book_name=book['название'],
        book_author=book['автор'],
        book_description=book['описание']
    )  
    await callback.answer('Добавляю в избранное.')




def register_user_handlers(dp):  
    dp.callback_query(F.data == 'choose_book')(choosing_book)
    dp.callback_query(F.data == 'learn_more')(learning_more)
    dp.callback_query(F.data == 'yesbook')(choosing_book2)
    dp.callback_query(F.data == 'cancel')(cancel_choice)
    # dp.callback_query(F.data == 'rare_art')(show_art)
    dp.callback_query(F.data.in_(['usmorning', 'usday', 'usevening', 'usnight']))(show_books)
    dp.callback_query(F.data.in_(['usmorning_prev', 'usday_prev', 'usevening_prev', 'usnight_prev']))(show_books_prev)
    dp.callback_query(F.data.in_(['add_fav_morning', 'add_fav_day', 'add_fav_evening', 'add_fav_night']))(add_book_to_favorites)

    register_favorites_handlers(dp)    